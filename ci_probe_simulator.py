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


def run(args, *, timeout=120, check=True):
    result = subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
    print('$', ' '.join(str(x) for x in args), flush=True)
    print(result.stdout[-16000:], flush=True)
    if check and result.returncode:
        raise RuntimeError(f'Command failed ({result.returncode}): {args[0]}')
    return result


def probe():
    report['architecture'] = run(['uname', '-m']).stdout.strip()
    if report['architecture'] != 'arm64':
        raise RuntimeError('ARM runner is required')
    report['xcode'] = run(['xcodebuild', '-version']).stdout
    runtimes = json.loads(run(['xcrun', 'simctl', 'list', 'runtimes', '-j']).stdout)['runtimes']
    (diagnostics/'runtimes.json').write_text(json.dumps(runtimes, indent=2))
    choices = [r for r in runtimes if r.get('isAvailable') and 'iOS' in r['name']]
    choices.sort(key=lambda r: tuple(map(int, r['version'].split('.'))), reverse=True)
    if not choices:
        raise RuntimeError('No installed iOS simulator runtime')
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
        run(['xcrun', 'simctl', 'io', device, 'screenshot', str(diagnostics/f'baseline-{delay}.png')], check=False)
    alive = run(['ps', '-p', str(pid), '-o', 'pid=,stat=,comm='], check=False) if pid else None
    report['process_alive'] = bool(alive and alive.returncode == 0)
    logs = run(['xcrun', 'simctl', 'spawn', device, 'log', 'show', '--last', '2m', '--style', 'compact',
        '--predicate', 'process == "DeepSeek Chat"'], timeout=60, check=False)
    (diagnostics/'application.log').write_text(logs.stdout)
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
