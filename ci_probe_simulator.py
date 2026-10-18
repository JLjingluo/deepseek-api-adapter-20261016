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
packaged_adapter = os.environ.get('PROBE_PACKAGED_ADAPTER') == 'true'
report['adapter_enabled'] = adapter_enabled
report['packaged_adapter'] = packaged_adapter


def run(args, *, timeout=120, check=True):
    started = time.monotonic()
    print('$', ' '.join(str(x) for x in args), flush=True)
    try:
        result = subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
    except subprocess.TimeoutExpired as error:
        output=error.stdout or ''
        if isinstance(output,bytes): output=output.decode(errors='replace')
        (diagnostics/('timeout-'+pathlib.Path(str(args[0])).name+'.log')).write_text(output[-128000:])
        report['steps'].append({'command':str(args[0]),'seconds':round(time.monotonic()-started,2),'timed_out':True})
        raise
    report['steps'].append({'command':str(args[0]),'seconds':round(time.monotonic()-started,2),'returncode':result.returncode})
    print(result.stdout[-16000:], flush=True)
    if check and result.returncode:
        report['failed_command'] = {'argv': [str(x) for x in args], 'output': result.stdout[-16000:]}
        raise RuntimeError(f'Command failed ({result.returncode}): {args[0]}')
    return result


def capture_startup_threads():
    processes = run(['pgrep', '-x', 'DeepSeek Chat'], check=False)
    for value in processes.stdout.split():
        if not value.isdecimal():
            continue
        destination = diagnostics/f'startup-{value}.sample.txt'
        sampled = run(['sample', value, '3', '-file', str(destination)], timeout=20, check=False)
        if sampled.returncode:
            run(['sudo', '-n', 'sample', value, '3', '-file', str(destination)], timeout=20, check=False)


def launch_application(device, bundle):
    args = ['xcrun', 'simctl', 'launch', '--terminate-running-process', device, bundle]
    process = subprocess.Popen(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        output, _ = process.communicate(timeout=8)
    except subprocess.TimeoutExpired:
        capture_startup_threads()
        try:
            output, _ = process.communicate(timeout=100)
        except subprocess.TimeoutExpired:
            process.kill()
            output, _ = process.communicate()
            report['launch_timed_out'] = True
            # Still collect screenshots, application logs and crash reports below.
    print('$', ' '.join(args), flush=True)
    print(output[-16000:], flush=True)
    return subprocess.CompletedProcess(args, process.returncode, output)


def build_simulator_adapter(app):
    """Build test-only observation code into the disposable simulator module."""
    from repack import add_library
    sdk = run(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path']).stdout.strip()
    objects = root/'objects'
    objects.mkdir(exist_ok=True)
    for source in [*pathlib.Path('Sources').glob('*.m'), pathlib.Path('Tests/RuntimeProbe.m')]:
        run(['xcrun', 'clang', '-target', 'arm64-apple-ios18.0-simulator', '-isysroot', sdk,
             '-ISources', '-DDSAPI_RUNTIME_DIAGNOSTICS=1', '-fobjc-arc', '-fmodules', '-O2', '-c', str(source),
             '-o', str(objects/(source.stem+'.o'))])
    library = app/'Frameworks/DSAPIAdapter.dylib'
    library.parent.mkdir(exist_ok=True)
    run(['xcrun', 'swiftc', '-sdk', sdk, '-target', 'arm64-apple-ios18.0-simulator',
         '-swift-version', '5', '-O', '-emit-library', 'Sources/DSRuntimeValidation.swift',
         'Tests/RuntimeProbe.swift', *[str(p) for p in objects.glob('*.o')],
         '-Xlinker', '-install_name', '-Xlinker', '@rpath/DSAPIAdapter.dylib',
         '-framework', 'Foundation', '-framework', 'UIKit', '-framework', 'Security', '-framework', 'AVFoundation', '-framework', 'NaturalLanguage',
         '-o', str(library)])
    info = plistlib.loads((app/'Info.plist').read_bytes())
    executable = app/info['CFBundleExecutable']
    patched, count = add_library(executable.read_bytes(), '@executable_path/Frameworks/DSAPIAdapter.dylib')
    executable.write_bytes(patched)
    report['unchanged_original_TEXT_sections'] = count


def add_runtime_observer(app):
    """Keep the packaged adapter's machine code; add a separate test observer."""
    from repack import add_library
    sdk = run(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path']).stdout.strip()
    object_file = root/'RuntimeObserver.o'
    run(['xcrun', 'clang', '-target', 'arm64-apple-ios18.0-simulator', '-isysroot', sdk,
        '-ISources', '-fobjc-arc', '-fmodules', '-O2', '-c', 'Tests/RuntimeProbe.m', '-o', str(object_file)])
    library = app/'Frameworks/DSRuntimeProbe.dylib'
    run(['xcrun', 'swiftc', '-sdk', sdk, '-target', 'arm64-apple-ios18.0-simulator',
        '-swift-version', '5', '-O', '-emit-library', 'Tests/RuntimeProbe.swift', str(object_file),
        '-Xlinker', '-install_name',
        '-Xlinker', '@rpath/DSRuntimeProbe.dylib', '-framework', 'Foundation',
        '-framework', 'UIKit', '-framework', 'Security', '-framework', 'AVFoundation', '-framework', 'NaturalLanguage', '-o', str(library)])
    info = plistlib.loads((app/'Info.plist').read_bytes())
    executable = app/info['CFBundleExecutable']
    patched, count = add_library(executable.read_bytes(), '@executable_path/Frameworks/DSRuntimeProbe.dylib')
    executable.write_bytes(patched)
    report['unchanged_original_TEXT_sections'] = count


def sign_simulator_app(app, entitlement_path):
    for extension in sorted(app.rglob('*.appex'), key=lambda p: len(p.parts), reverse=True):
        run(['codesign', '--force', '--sign', '-', '--deep', '--entitlements', str(entitlement_path), str(extension)])
    run(['codesign', '--force', '--sign', '-', '--deep', '--entitlements', str(entitlement_path), str(app)])


def original_build_versions(path):
    data = path.read_bytes()
    cursor = 32
    for _ in range(struct.unpack_from('<I', data, 16)[0]):
        command, length = struct.unpack_from('<II', data, cursor)
        if length < 8 or cursor+length > len(data):
            raise RuntimeError('Invalid Mach-O command bounds: '+str(path))
        if command == 0x32:
            minimum, sdk = struct.unpack_from('<II', data, cursor+12)
            break
        if command == 0x25:
            minimum, sdk = struct.unpack_from('<II', data, cursor+8)
            break
        cursor += length
    else:
        raise RuntimeError('No original iOS build version: '+str(path))
    def version(value):
        return f'{value >> 16}.{(value >> 8) & 255}.{value & 255}'
    return version(minimum), version(sdk)


def select_simulator_toolchain():
    # This input was linked with SDK 26 and strongly imports libswiftWebKit.
    # Selecting the default Xcode 16 / iOS 18 runtime cannot load that import.
    from ci_xcode import installed_toolchains
    report['available_toolchains'] = []
    for _, developer in installed_toolchains():
        os.environ['DEVELOPER_DIR'] = str(developer)
        result = run(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version'], check=False)
        if result.returncode:
            continue
        sdk = result.stdout.strip()
        report['available_toolchains'].append({'developer_dir': str(developer), 'sdk': sdk})
        if tuple(map(int, sdk.split('.'))) < (26, 0):
            continue
        result = run(['xcrun', 'simctl', 'list', 'runtimes', '-j'], check=False)
        if result.returncode:
            continue
        runtimes = json.loads(result.stdout)['runtimes']
        if any(r.get('isAvailable') and 'iOS' in r['name'] and
               r['version'].split('.')[:2] == sdk.split('.')[:2] for r in runtimes):
            report['developer_dir'] = str(developer)
            return
    raise RuntimeError('No installed Xcode 26+ with a matching available iOS simulator runtime')


def collect_ui_observations(device):
    from ci_ui_probe import create_project
    project = create_project(root/'UIProbe')
    results = root/'UIResult.xcresult'
    focus = os.environ.get('PROBE_UI_TEST_FOCUS', 'all')
    if focus not in ('', 'all', 'settings', 'regeneration', 'startup', 'switching', 'attachment'):
        raise RuntimeError('Unknown native test focus')
    selected = {'settings': 'testNativeSettings', 'regeneration': 'testNativeRegeneration', 'startup': 'testNativeApp', 'switching': 'testNativeServiceSwitching', 'attachment': 'testNativeAttachment'}.get(focus)
    target = 'NativeUIProbeUITests/CaptureTests' + ('/'+selected if selected else '')
    arguments = ['xcodebuild', '-project', str(project), '-scheme', 'NativeUIProbe',
        '-destination', 'platform=iOS Simulator,id='+device, '-derivedDataPath', str(root/'UIBuild'),
        '-resultBundlePath', str(results), '-only-testing:'+target,
        'test']
    conditions=[]
    if adapter_enabled: conditions.append('DSAPI_ADAPTER_UI')
    if report.get('mock_api_base_url'): conditions.append('DSAPI_MOCK_UI')
    if conditions: arguments.insert(-1, 'SWIFT_ACTIVE_COMPILATION_CONDITIONS='+' '.join(conditions))
    try:
        outcome = run(arguments, timeout=600, check=False)
    except subprocess.TimeoutExpired as error:
        output=error.stdout or ''
        if isinstance(output,bytes): output=output.decode(errors='replace')
        outcome=subprocess.CompletedProcess(arguments,124,output)
        report['ui_test_timed_out']=True
        capture_startup_threads()
    (diagnostics/'ui-test.log').write_text(outcome.stdout[-128000:])
    highlights=[line[:1500] for line in outcome.stdout.splitlines() if any(marker in line for marker in
        ('Test Case ', ' error: ', 'DSAPI_FONT_CHANGE=', 'DSAPI_READ_ALOUD_LABEL=', 'DSAPI_API_SETTINGS_VISITED=', 'DSAPI_SWITCH_CYCLE='))]
    (diagnostics/'ui-case-summary.log').write_text('\n'.join(highlights)[-48000:])
    report['ui_test_exit_code'] = outcome.returncode
    if outcome.returncode: capture_startup_threads()
    report['ui_test_scope'] = ('native '+focus+' only' if selected else
        ('native streaming, cancellation, read-aloud and settings' if report.get('mock_api_base_url') else 'startup and settings'))
    if results.exists():
        exported = run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(results),
            '--output-path', str(diagnostics/'UIAttachments')], timeout=90, check=False)
        report['ui_attachment_export_exit_code'] = exported.returncode


def probe():
    report['architecture'] = run(['uname', '-m']).stdout.strip()
    if report['architecture'] != 'arm64':
        raise RuntimeError('ARM runner is required')
    select_simulator_toolchain()
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
    if adapter_enabled and os.environ.get('PROBE_MOCK_API') == 'true':
        from ci_mock_api import start_mock_api
        server, base_url = start_mock_api(root, diagnostics, device, run)
        report['mock_api_base_url'] = base_url
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
    if packaged_adapter and not adapter_enabled:
        raise RuntimeError('A packaged adapter probe requires adapter mode')
    if packaged_adapter:
        import hashlib
        library = app/'Frameworks/DSAPIAdapter.dylib'
        if not library.is_file():
            raise RuntimeError('Candidate does not contain its adapter library')
        report['packaged_adapter_sha256'] = hashlib.sha256(library.read_bytes()).hexdigest()
    elif adapter_enabled:
        build_simulator_adapter(app)
    # Simulator-only ad-hoc signing; no developer certificate or account involved.
    # Device App Group entitlements are restricted on the macOS host and cannot
    # be granted by this ad-hoc test signature. Do not copy them into it.
    entitlements = {'com.apple.security.app-sandbox': True, 'com.apple.security.network.client': True}
    report['simulator_entitlements'] = list(entitlements)
    entitlement_path = root/'simulator-entitlements.plist'
    entitlement_path.write_bytes(plistlib.dumps(entitlements))
    converted = []
    report['preserved_build_versions'] = []
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
        minimum, sdk = original_build_versions(path)
        # UIKit compatibility behavior depends on the main executable's linked
        # SDK. Preserve it so a simulator comparison does not select old UI.
        report['preserved_build_versions'].append({'path': str(path.relative_to(app)), 'minimum': minimum, 'sdk': sdk})
        run(['xcrun', 'vtool', '-arch', 'arm64', '-set-build-version', '7', minimum, sdk,
             '-replace', '-output', str(output), str(path)])
        output.replace(path)
        path.chmod(0o755)
        run(['codesign', '--force', '--sign', '-', str(path)])
        converted.append(str(path.relative_to(app)))
    report['converted_macho_files'] = converted
    if packaged_adapter:
        add_runtime_observer(app)
    run(['xattr', '-cr', str(app)])
    sign_simulator_app(app, entitlement_path)
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
    startup_mode=os.environ.get('PROBE_STARTUP_MODE','original')
    if startup_mode not in ('original','api'): raise RuntimeError('Invalid startup mode')
    container=run(['xcrun','simctl','get_app_container',device,bundle,'data']).stdout.strip()
    preferences=pathlib.Path(container)/'Library/Preferences'/(bundle+'.plist')
    preferences.parent.mkdir(parents=True,exist_ok=True)
    values=plistlib.loads(preferences.read_bytes()) if preferences.exists() else {}
    values['DSAPIAdapter.configuration.v1']={'enabled':startup_mode=='api'}
    if report.get('mock_api_base_url'):
        values['DSAPIAdapter.localTestFixture']={'baseURL':report['mock_api_base_url']}
        values['DSAPIAdapter.configuration.v1'].update({'baseURL':report['mock_api_base_url'],'model':'ci-mock-model','timeout':180,'requestUsage':True})
    preferences.write_bytes(plistlib.dumps(values))
    report['startup_api_mode']=startup_mode=='api'
    launch = launch_application(device, bundle)
    report['signing_attempts'] = [{'entitlements': entitlements, 'launch_exit_code': launch.returncode}]
    if launch.returncode and not report.get('launch_timed_out'):
        # One controlled comparison: no entitlements. The device get-task-allow
        # entitlement was rejected by host AMFI in the previous investigation.
        (diagnostics/'launch-sandbox.txt').write_text(launch.stdout)
        entitlement_path.write_bytes(plistlib.dumps({}))
        sign_simulator_app(app, entitlement_path)
        run(['xcrun', 'simctl', 'install', device, str(app)])
        launch = launch_application(device, bundle)
        report['signing_attempts'].append({'entitlements': {}, 'launch_exit_code': launch.returncode})
        report['simulator_entitlements'] = []
        signature = run(['codesign', '-d', '--verbose=4', '--entitlements', ':-', str(app)], check=False)
        (diagnostics/'signature-metadata-final.txt').write_text(signature.stdout)
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
    # A cold simulator can start the app only after simctl's launch command has
    # timed out. XCTest's foreground + responsive-control assertions are the
    # authoritative runtime acceptance, not parsing a missing CLI PID line.
    report['initial_process_alive']=report['process_alive']
    collect_ui_observations(device)
    if report.get('ui_test_exit_code')==0: report['process_alive']=True
    if adapter_enabled and runtime_report.is_file():
        shutil.copy2(runtime_report, diagnostics/'runtime-probe-after-ui.json')
    after_logs = run(['xcrun', 'simctl', 'spawn', device, 'log', 'show', '--last', '3m', '--style', 'compact',
        '--predicate', 'process == \"DeepSeek Chat\"'], timeout=60, check=False)
    (diagnostics/'application-after-ui.log').write_text(after_logs.stdout)
    report['result'] = 'original binary remained running; screenshots require inspection'
    if report.get('ui_test_exit_code') != 0:
        raise RuntimeError('Native UI acceptance assertions failed; see ui-test.log')


if __name__ == '__main__':
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
