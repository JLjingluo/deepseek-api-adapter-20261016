"""Experimental baseline probe. Changes only a disposable simulator copy.

This is not an IPA delivery build and success does not establish device parity.
"""
import json
import os
import pathlib
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import time
import zipfile

root = pathlib.Path('sim-probe')
diagnostics = pathlib.Path('diagnostics')
diagnostics.mkdir(exist_ok=True)
report = {'verification': 'experimental original-binary simulator baseline', 'steps': []}
adapter_enabled = os.environ.get('PROBE_ADAPTER') == 'true'
report['adapter_enabled'] = adapter_enabled


def run(args, *, timeout=120, check=True):
    result = subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
    print('$', ' '.join(str(x) for x in args), flush=True)
    print(result.stdout[-16000:], flush=True)
    if check and result.returncode:
        raise RuntimeError(f'Command failed ({result.returncode}): {args[0]}')
    return result


def build_simulator_adapter(app):
    """Build test-only observation code into the disposable simulator module."""
    from repack import add_library
    sdk = run(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path']).stdout.strip()
    objects = root/'objects'
    objects.mkdir(exist_ok=True)
    for source in [*pathlib.Path('Sources').glob('*.m'), pathlib.Path('Tests/RuntimeProbe.m')]:
        run(['xcrun', 'clang', '-target', 'arm64-apple-ios18.0-simulator', '-isysroot', sdk,
             '-ISources', '-fobjc-arc', '-fmodules', '-O2', '-c', str(source),
             '-o', str(objects/(source.stem+'.o'))])
    library = app/'Frameworks/DSAPIAdapter.dylib'
    library.parent.mkdir(exist_ok=True)
    run(['xcrun', 'swiftc', '-sdk', sdk, '-target', 'arm64-apple-ios18.0-simulator',
         '-swift-version', '5', '-O', '-emit-library', 'Sources/DSRuntimeValidation.swift',
         'Tests/RuntimeProbe.swift', *[str(p) for p in objects.glob('*.o')],
         '-Xlinker', '-install_name', '-Xlinker', '@rpath/DSAPIAdapter.dylib',
         '-framework', 'Foundation', '-framework', 'UIKit', '-framework', 'Security',
         '-o', str(library)])
    info = plistlib.loads((app/'Info.plist').read_bytes())
    executable = app/info['CFBundleExecutable']
    patched, count = add_library(executable.read_bytes(), '@executable_path/Frameworks/DSAPIAdapter.dylib')
    executable.write_bytes(patched)
    report['unchanged_original_TEXT_sections'] = count


def probe():
    report['architecture'] = run(['uname', '-m']).stdout.strip()
    if report['architecture'] != 'arm64':
        raise RuntimeError('ARM runner is required')
    report['xcode'] = run(['xcodebuild', '-version']).stdout
    sdk_version = run(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version']).stdout.strip()
    report['simulator_sdk'] = sdk_version
    runtimes = json.loads(run(['xcrun', 'simctl', 'list', 'runtimes', '-j']).stdout)['runtimes']
    (diagnostics/'runtimes.json').write_text(json.dumps(runtimes, indent=2))
    # Use the runtime belonging to the selected Xcode rather than an unrelated,
    # newer runtime that happens to be preinstalled in the runner image.
    choices = [r for r in runtimes if r.get('isAvailable') and 'iOS' in r['name']
               and r['version'].split('.')[:2] == sdk_version.split('.')[:2]]
    choices.sort(key=lambda r: tuple(map(int, r['version'].split('.'))), reverse=True)
    if not choices:
        raise RuntimeError('No installed iOS simulator runtime matching the selected SDK')
    runtime = choices[0]
    types = json.loads(run(['xcrun', 'simctl', 'list', 'devicetypes', '-j']).stdout)['devicetypes']
    phones = [d for d in types if d['name'].startswith('iPhone') and 'SE' not in d['name']]
    preferred = next((d for d in phones if d['name'] == 'iPhone 16 Pro'), phones[-1])
    device_type = preferred['identifier']
    report['runtime'] = runtime['identifier']
    report['device_type'] = device_type
    device = run(['xcrun', 'simctl', 'create', 'OriginalBinaryProbe', device_type, runtime['identifier']]).stdout.strip()
    report['device'] = device
    run(['xcrun', 'simctl', 'boot', device])
    run(['xcrun', 'simctl', 'bootstatus', device, '-b'], timeout=240)
    root.mkdir(exist_ok=True)
    with zipfile.ZipFile(sys.argv[1]) as package:
        for info in package.infolist():
            path = pathlib.PurePosixPath(info.filename)
            if path.is_absolute() or '..' in path.parts:
                raise RuntimeError('Invalid archive member path')
            target = pathlib.Path(package.extract(info, root))
            mode = (info.external_attr >> 16) & 0o777
            if mode:
                target.chmod(mode)
    app = next((root/'Payload').glob('*.app'))
    # The simulator copy needs simulator metadata. The delivery input is untouched.
    for info in app.rglob('Info.plist'):
        try:
            values = plistlib.loads(info.read_bytes())
        except Exception:
            continue
        if values.get('CFBundleExecutable'):
            values['CFBundleSupportedPlatforms'] = ['iPhoneSimulator']
            values['DTPlatformName'] = 'iphonesimulator'
            info.write_bytes(plistlib.dumps(values))
    main_info = plistlib.loads((app/'Info.plist').read_bytes())
    bundle = main_info['CFBundleIdentifier']
    report['bundle_id'] = bundle
    if adapter_enabled:
        build_simulator_adapter(app)
    entitlement_result = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(app)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        raw = entitlement_result.stdout
        start = raw.find(b'<?xml')
        entitlement_values = plistlib.loads(raw[start:] if start >= 0 else raw)
    except Exception:
        entitlement_values = {}
    # Simulator-only ad-hoc signing; no developer certificate or account involved.
    entitlements = {'get-task-allow': True}
    for key in ('com.apple.security.application-groups', 'keychain-access-groups'):
        if key in entitlement_values:
            entitlements[key] = entitlement_values[key]
    entitlement_path = root/'simulator-entitlements.plist'
    entitlement_path.write_bytes(plistlib.dumps(entitlements))
    converted = []
    for path in list(app.rglob('*')):
        if not path.is_file() or path.is_symlink():
            continue
        with path.open('rb') as handle:
            magic = handle.read(4)
        if magic not in (b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
            continue
        archs = run(['lipo', '-archs', str(path)]).stdout.strip().split()
        if 'arm64' not in archs:
            raise RuntimeError('No arm64 slice: '+str(path))
        if len(archs) > 1:
            thin = path.with_name(path.name+'.thin')
            run(['lipo', str(path), '-thin', 'arm64', '-output', str(thin)])
            thin.replace(path)
        output = path.with_name(path.name+'.simulator')
        run(['xcrun', 'vtool', '-arch', 'arm64', '-set-build-version', '7', '18.0', '18.0',
             '-replace', '-output', str(output), str(path)])
        output.replace(path)
        path.chmod(0o755)
        run(['codesign', '--force', '--sign', '-', str(path)])
        converted.append(str(path.relative_to(app)))
    report['converted_macho_files'] = converted
    run(['xattr', '-cr', str(app)])
    for extension in sorted(app.rglob('*.appex'), key=lambda p: len(p.parts), reverse=True):
        run(['codesign', '--force', '--sign', '-', '--deep', '--entitlements', str(entitlement_path), str(extension)])
    run(['codesign', '--force', '--sign', '-', '--deep', '--entitlements', str(entitlement_path), str(app)])
    verification = run(['codesign', '--verify', '--deep', '--strict', '--verbose=4', str(app)], check=False)
    (diagnostics/'signature-verification.txt').write_text(verification.stdout)
    report['signature_verify_exit_code'] = verification.returncode
    signature = run(['codesign', '-d', '--verbose=4', '--entitlements', ':-', str(app)], check=False)
    (diagnostics/'signature-metadata.txt').write_text(signature.stdout)
    install = run(['xcrun', 'simctl', 'install', device, str(app)], check=False)
    report['install_exit_code'] = install.returncode
    (diagnostics/'install.txt').write_text(install.stdout)
    if install.returncode:
        raise RuntimeError('Simulator installation rejected the converted original binary')
    launch = run(['xcrun', 'simctl', 'launch', '--terminate-running-process', device, bundle], check=False)
    report['launch_exit_code'] = launch.returncode
    (diagnostics/'launch.txt').write_text(launch.stdout)
    match = re.search(r':\s*(\d+)\s*$', launch.stdout)
    pid = int(match.group(1)) if match else None
    for delay in (3, 8):
        time.sleep(delay)
        mode = 'adapter' if adapter_enabled else 'baseline'
        run(['xcrun', 'simctl', 'io', device, 'screenshot', str(diagnostics/f'{mode}-{delay}.png')], check=False)
    if adapter_enabled:
        container = run(['xcrun', 'simctl', 'get_app_container', device, bundle, 'data'], check=False)
        runtime_report = pathlib.Path(container.stdout.strip())/'Documents/DSAPI-runtime-probe.json'
        if container.returncode == 0 and runtime_report.is_file():
            shutil.copy2(runtime_report, diagnostics/'runtime-probe.json')
            report['native_decoder_report_collected'] = True
        else:
            report['native_decoder_report_collected'] = False
    alive = run(['ps', '-p', str(pid), '-o', 'pid=,stat=,comm='], check=False) if pid else None
    report['process_alive'] = bool(alive and alive.returncode == 0)
    logs = run(['xcrun', 'simctl', 'spawn', device, 'log', 'show', '--last', '2m', '--style', 'compact',
        '--predicate', 'process == "DeepSeek Chat"'], timeout=60, check=False)
    (diagnostics/'application.log').write_text(logs.stdout)
    host_logs = run(['log', 'show', '--last', '3m', '--style', 'compact', '--predicate',
        'eventMessage CONTAINS[c] "DeepSeek Chat" OR eventMessage CONTAINS[c] "com.deepseek.chat"'],
        timeout=60, check=False)
    (diagnostics/'host-signing.log').write_text(host_logs.stdout)
    for path in pathlib.Path.home().joinpath('Library/Logs/DiagnosticReports').glob('*'):
        if path.is_file() and ('DeepSeek' in path.name or path.stat().st_mtime > time.time()-180):
            if path.stat().st_size < 8*1024*1024:
                shutil.copy2(path, diagnostics/path.name)
    if not report['process_alive']:
        raise RuntimeError('Converted original app did not remain running')
    report['result'] = 'original binary remained running; screenshots require inspection'


try:
    probe()
except Exception as error:
    report['error'] = str(error)
    report['result'] = 'baseline probe failed; no UI equivalence established'
finally:
    (diagnostics/'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print(json.dumps(report, ensure_ascii=False, indent=2), flush=True)
if 'error' in report:
    sys.exit(1)
