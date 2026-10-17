"""Local HTTPS OpenAI-compatible fixture; no external API credentials needed."""
import http.server
import json
import os
import pathlib
import ssl
import threading
import time


def start_mock_api(root, diagnostics, device, run):
    root = pathlib.Path(root)/'mock-api'
    root.mkdir(parents=True, exist_ok=True)
    (root/'root.cnf').write_text('''[req]
prompt=no
distinguished_name=dn
x509_extensions=ca
[dn]
CN=DSAPI disposable test CA
[ca]
basicConstraints=critical,CA:TRUE
keyUsage=critical,keyCertSign,cRLSign
subjectKeyIdentifier=hash
''')
    (root/'leaf.cnf').write_text('''basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost,IP:127.0.0.1
''')
    run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1', '-sha256',
         '-keyout', str(root/'root.key'), '-out', str(root/'root.pem'), '-config', str(root/'root.cnf')])
    run(['openssl', 'req', '-new', '-newkey', 'rsa:2048', '-nodes', '-keyout', str(root/'server.key'),
         '-out', str(root/'server.csr'), '-subj', '/CN=localhost'])
    run(['openssl', 'x509', '-req', '-in', str(root/'server.csr'), '-CA', str(root/'root.pem'),
         '-CAkey', str(root/'root.key'), '-CAcreateserial', '-out', str(root/'server.pem'),
         '-days', '1', '-sha256', '-extfile', str(root/'leaf.cnf')])
    run(['xcrun', 'simctl', 'keychain', device, 'add-root-cert', str(root/'root.pem')])
    records = []
    lock = threading.Lock()

    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.1'

        def log_message(self, *args):
            pass

        def do_POST(self):
            length = int(self.headers.get('Content-Length', '0'))
            if length > 1024*1024:
                self.send_error(413)
                return
            try:
                body = json.loads(self.rfile.read(length))
            except (ValueError, TypeError):
                self.send_error(400)
                return
            messages = body.get('messages', [])
            record = {'path': self.path, 'model': body.get('model'), 'stream': body.get('stream'),
                'message_count': len(messages), 'roles': [m.get('role') for m in messages],
                'dummy_authorization_valid': self.headers.get('Authorization') == 'Bearer ci-dummy-key'}
            with lock:
                records.append(record)
                (pathlib.Path(diagnostics)/'mock-api.json').write_text(json.dumps(records, indent=2))
            if self.path != '/v1/chat/completions' or not record['dummy_authorization_valid']:
                self.send_error(401)
                return
            self.send_response(200)
            self.send_header('Content-Type', 'text/event-stream; charset=utf-8')
            self.send_header('Connection', 'close')
            self.end_headers()
            try:
                for index, text in enumerate(['首段流式回复', '：流式输出正常。', '\n', '这条消息来自本地模拟接口。']):
                    event = {'id': 'ci-mock', 'choices': [{'index': 0, 'delta': {'content': text}, 'finish_reason': None}]}
                    wire = ('data: '+json.dumps(event, ensure_ascii=False)+'\n\n').encode()
                    # Deliberately fragment UTF-8 bytes and JSON across reads.
                    for offset in range(0, len(wire), 13):
                        self.wfile.write(wire[offset:offset+13])
                        self.wfile.flush()
                    time.sleep(5 if index == 0 else 0.12)
                self.wfile.write(b'data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n')
                self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                pass
            self.close_connection = True

    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    server.daemon_threads = True
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(root/'server.pem', root/'server.key')
    server.socket = context.wrap_socket(server.socket, server_side=True)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base_url = f'https://127.0.0.1:{server.server_port}/v1'
    os.environ['SIMCTL_CHILD_DSAPI_TEST_BASE_URL'] = base_url
    return server, base_url
