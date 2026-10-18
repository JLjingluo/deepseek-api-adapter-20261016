"""Generate a disposable Xcode UI test project for an already installed app.

The small host belongs only to the test runner. The test launches the supplied
app by bundle identifier; it does not replace any of the original app's UI.
"""
import hashlib
import json
import pathlib


def create_project(root):
    root = pathlib.Path(root)
    root.mkdir(parents=True, exist_ok=True)
    objects = {}

    def add(key_name, isa, **values):
        key = hashlib.sha256(key_name.encode()).hexdigest()[:24].upper()
        objects[key] = {'isa': isa, **values}
        return key

    def configurations(name, settings):
        entries = [add(name+mode, 'XCBuildConfiguration', name=mode, buildSettings=settings)
                   for mode in ('Debug', 'Release')]
        return add(name+'Configurations', 'XCConfigurationList', buildConfigurations=entries,
                   defaultConfigurationIsVisible=0, defaultConfigurationName='Debug')

    common = {'SDKROOT': 'iphoneos', 'IPHONEOS_DEPLOYMENT_TARGET': '18.0', 'SWIFT_VERSION': '5.0',
              'CLANG_ENABLE_MODULES': 'YES', 'TARGETED_DEVICE_FAMILY': '1,2',
              'CODE_SIGN_IDENTITY': '-', 'CODE_SIGNING_ALLOWED': 'YES',
              'CODE_SIGN_STYLE': 'Manual', 'ONLY_ACTIVE_ARCH': 'YES', 'ARCHS': 'arm64',
              'GENERATE_INFOPLIST_FILE': 'YES'}
    host_source = add('HostSource', 'PBXFileReference', lastKnownFileType='sourcecode.swift',
                      path='ProbeHost.swift', sourceTree='<group>')
    test_source = add('TestSource', 'PBXFileReference', lastKnownFileType='sourcecode.swift',
                      path='NativeUIProbe.swift', sourceTree='<group>')
    host_product = add('HostProduct', 'PBXFileReference', explicitFileType='wrapper.application',
                       path='ProbeHost.app', sourceTree='BUILT_PRODUCTS_DIR', includeInIndex=0)
    test_product = add('TestProduct', 'PBXFileReference', explicitFileType='wrapper.cfbundle',
                       path='NativeUIProbeUITests.xctest', sourceTree='BUILT_PRODUCTS_DIR', includeInIndex=0)
    products = add('Products', 'PBXGroup', name='Products', children=[host_product, test_product], sourceTree='<group>')
    group = add('MainGroup', 'PBXGroup', children=[host_source, test_source, products], sourceTree='<group>')

    def source_phase(name, reference):
        file = add(name+'BuildFile', 'PBXBuildFile', fileRef=reference)
        return add(name+'Sources', 'PBXSourcesBuildPhase', buildActionMask=2147483647,
                   files=[file], runOnlyForDeploymentPostprocessing=0)

    host = add('HostTarget', 'PBXNativeTarget', name='ProbeHost', productName='ProbeHost',
               productReference=host_product, productType='com.apple.product-type.application',
               buildConfigurationList=configurations('Host', {**common, 'PRODUCT_NAME': '$(TARGET_NAME)',
                   'PRODUCT_BUNDLE_IDENTIFIER': 'local.dsapi.probehost', 'INFOPLIST_KEY_UILaunchScreen_Generation': 'YES'}),
               buildPhases=[source_phase('Host', host_source)], buildRules=[], dependencies=[])
    project_id = hashlib.sha256(b'Project').hexdigest()[:24].upper()
    proxy = add('HostProxy', 'PBXContainerItemProxy', containerPortal=project_id, proxyType=1,
                remoteGlobalIDString=host, remoteInfo='ProbeHost')
    dependency = add('HostDependency', 'PBXTargetDependency', target=host, targetProxy=proxy)
    tests = add('TestTarget', 'PBXNativeTarget', name='NativeUIProbeUITests', productName='NativeUIProbeUITests',
                productReference=test_product, productType='com.apple.product-type.bundle.ui-testing',
                buildConfigurationList=configurations('Tests', {**common, 'PRODUCT_NAME': '$(TARGET_NAME)',
                    'PRODUCT_BUNDLE_IDENTIFIER': 'local.dsapi.uiprobe', 'TEST_TARGET_NAME': 'ProbeHost'}),
                buildPhases=[source_phase('Tests', test_source)], buildRules=[], dependencies=[dependency])
    add('Project', 'PBXProject', attributes={'LastUpgradeCheck': '2600'},
        buildConfigurationList=configurations('Project', {}), compatibilityVersion='Xcode 14.0',
        developmentRegion='en', knownRegions=['en', 'Base'], mainGroup=group, productRefGroup=products,
        projectDirPath='', projectRoot='', targets=[host, tests])

    def plist(value):
        if isinstance(value, dict):
            return '{\n'+'\n'.join(json.dumps(k)+' = '+plist(v)+';' for k, v in value.items())+'\n}'
        if isinstance(value, list):
            return '('+','.join(plist(v) for v in value)+')'
        return str(value) if isinstance(value, int) else json.dumps(value)

    project = root/'NativeUIProbe.xcodeproj'
    project.mkdir(exist_ok=True)
    (project/'project.pbxproj').write_text('// !$*UTF8*$!\n'+plist({
        'archiveVersion': 1, 'classes': {}, 'objectVersion': 56, 'objects': objects, 'rootObject': project_id}))
    (root/'ProbeHost.swift').write_text('''import UIKit
@main final class ProbeHost: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = UIViewController()
        window?.makeKeyAndVisible()
        return true
    }
}
''')
    (root/'NativeUIProbe.swift').write_bytes(pathlib.Path('Tests/NativeUIProbe.swift').read_bytes())
    schemes = project/'xcshareddata/xcschemes'
    schemes.mkdir(parents=True, exist_ok=True)

    def reference(identifier, name, product):
        return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{identifier}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:NativeUIProbe.xcodeproj"/>'

    host_ref = reference(host, 'ProbeHost', 'ProbeHost.app')
    test_ref = reference(tests, 'NativeUIProbeUITests', 'NativeUIProbeUITests.xctest')
    (schemes/'NativeUIProbe.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="NO" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">{host_ref}</BuildActionEntry>
<BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">{test_ref}</BuildActionEntry>
</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
<Testables><TestableReference skipped="NO">{test_ref}</TestableReference></Testables><MacroExpansion>{host_ref}</MacroExpansion>
</TestAction></Scheme>''')
    return project
