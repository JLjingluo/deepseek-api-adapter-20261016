"""Local HTTPS OpenAI-compatible fixture; no external API credentials needed."""
import http.server
import json
import os
import pathlib
import ssl
import threading
import time
import urllib.request
import urllib.error


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

        def do_GET(self):
            if self.path!='/v1/models' or self.headers.get('Authorization')!='Bearer ci-dummy-key':
                self.send_error(401); return
            body=json.dumps({'object':'list','data':[{'id':'ci-mock-model'},{'id':'ci-mock-reasoner'}]}).encode()
            self.send_response(200); self.send_header('Content-Type','application/json'); self.send_header('Content-Length',str(len(body))); self.end_headers(); self.wfile.write(body)
            with lock:
                (pathlib.Path(diagnostics)/'model-list-request.json').write_text(json.dumps({'path':self.path,'dummy_authorization_valid':True,'models_returned':2}))

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
            image_case=bool(messages and isinstance(messages[-1].get('content'),list) and any(p.get('type')=='image_url' for p in messages[-1]['content'] if isinstance(p,dict)))
            cancel_case=bool(messages and messages[-1].get('content') == 'API cancellation test')
            record = {'path': self.path, 'model': body.get('model'), 'stream': body.get('stream'),
                'message_count': len(messages), 'roles': [m.get('role') for m in messages],
                'image_parts':sum(1 for m in messages if isinstance(m.get('content'),list) for p in m['content'] if isinstance(p,dict) and p.get('type')=='image_url'),
                'scenario': 'image' if image_case else ('cancel' if cancel_case else ('regenerate' if messages and messages[-1].get('content') == 'API regeneration test' else ('cloud' if messages and messages[-1].get('content')=='API cloud continuation test' else 'normal'))),
                'dummy_authorization_valid': self.headers.get('Authorization') == 'Bearer ci-dummy-key'}
            with lock:
                records.append(record)
                (pathlib.Path(diagnostics)/'mock-api.json').write_text(json.dumps(records, indent=2))
            if self.path != '/v1/chat/completions' or not record['dummy_authorization_valid']:
                self.send_error(401)
                return
            text=messages[-1].get('content') if messages else None
            diagnostic_status={'API diagnostic 401 test':401,'API diagnostic 402 test':402}.get(text) if isinstance(text,str) else None
            if diagnostic_status:
                record['scenario']='diagnostic'; record['http_status']=diagnostic_status
                with lock: (pathlib.Path(diagnostics)/'mock-api.json').write_text(json.dumps(records,indent=2))
                payload=json.dumps({'error':{'code':'invalid_api_key' if diagnostic_status==401 else 'insufficient_quota','message':'ci-dummy-key must never appear in copied diagnostics'}}).encode()
                self.send_response(diagnostic_status); self.send_header('Content-Type','application/json'); self.send_header('Content-Length',str(len(payload))); self.end_headers(); self.wfile.write(payload); return
            if os.environ.get('PROBE_LIVE_API')=='true':
                secret=os.environ.get('TEST_API_KEY','')
                if not secret: self.send_error(503); return
                outgoing=dict(body); outgoing['model']='deepseek-chat'
                record['provider_model']='deepseek-chat'; record['live_provider']='https://api.deepseek.com/v1'
                request=urllib.request.Request('https://api.deepseek.com/v1/chat/completions',
                    data=json.dumps(outgoing).encode(),headers={'Authorization':'Bearer '+secret,'Content-Type':'application/json'})
                try:
                    with urllib.request.urlopen(request,timeout=90) as upstream:
                        record['provider_http_status']=upstream.status
                        self.send_response(upstream.status)
                        self.send_header('Content-Type','text/event-stream; charset=utf-8')
                        self.send_header('Connection','close'); self.end_headers()
                        for wire in upstream:
                            if wire.startswith(b'data:'):
                                try:
                                    value=json.loads(wire[5:].strip())
                                    if value.get('usage'): record['usage']=value['usage']
                                except (ValueError,TypeError): pass
                            self.wfile.write(wire); self.wfile.flush()
                        record['completed']=True
                except urllib.error.HTTPError as error:
                    record['provider_http_status']=error.code; self.send_error(error.code)
                except (BrokenPipeError,ConnectionResetError,ssl.SSLError): record['disconnected_before_finish']=True
                except (urllib.error.URLError,TimeoutError): record['provider_error']='network'; self.send_error(502)
                finally:
                    self.close_connection=True
                    with lock: (pathlib.Path(diagnostics)/'mock-api.json').write_text(json.dumps(records,indent=2))
                return
            self.send_response(200)
            self.send_header('Content-Type', 'text/event-stream; charset=utf-8')
            self.send_header('Connection', 'close')
            self.end_headers()
            try:
                fragments=['取消前片段：这段文字用于检查停止生成后已显示内容的保留，以及长句朗读时播放状态和停止按钮的实际变化。', '取消后不应出现'] if cancel_case else ['首段流式回复', '：流式输出正常。', '\n', '这条消息来自本地模拟接口。']
                if image_case: fragments=['图片已由 API 接收','：红色方块。']
                for index, text in enumerate(fragments):
                    event = {'id': 'ci-mock', 'choices': [{'index': 0, 'delta': {'content': text}, 'finish_reason': None}]}
                    wire = ('data: '+json.dumps(event, ensure_ascii=False)+'\n\n').encode()
                    # Deliberately fragment UTF-8 bytes and JSON across reads.
                    for offset in range(0, len(wire), 13):
                        self.wfile.write(wire[offset:offset+13])
                        self.wfile.flush()
                    time.sleep((15 if cancel_case else 5) if index == 0 else 0.12)
                self.wfile.write(b'data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}\n\ndata: {"choices":[],"usage":{"prompt_tokens":5,"completion_tokens":12,"total_tokens":17}}\n\ndata: [DONE]\n\n')
                self.wfile.flush()
                record['completed']=True
            except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
                record['disconnected_before_finish']=True
            finally:
                with lock:
                    (pathlib.Path(diagnostics)/'mock-api.json').write_text(json.dumps(records, indent=2))
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
