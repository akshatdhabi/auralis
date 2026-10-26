#!/usr/bin/env python3
"""Deterministic Xcode project generator. No third-party project tool required."""
from pathlib import Path
import hashlib
root = Path(__file__).resolve().parent.parent
project = root / 'Auralis.xcodeproj'
project.mkdir(exist_ok=True)
objects = {}
def uid(key): return hashlib.sha256(key.encode()).hexdigest()[:24].upper()
def add(key, value):
    ident = uid(key); objects[ident] = value; return ident
def quote(s): return '"' + str(s).replace('\\', '\\\\').replace('"', '\\"') + '"'
def arr(items): return '(' + ', '.join(items) + ')'
def ref(key): return uid(key)
source_refs, source_builds = [], []
for path in sorted((root / 'Auralis').rglob('*.swift')):
    rel = path.relative_to(root).as_posix()
    source_refs.append(add(rel, '{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = '+quote(rel)+'; sourceTree = SOURCE_ROOT;}'))
    source_builds.append(add('build:'+rel, '{isa = PBXBuildFile; fileRef = '+ref(rel)+';}'))
resources, resource_builds = [], []
for path, kind in [('Auralis/Resources/LyricsAdapter.js', 'sourcecode.javascript'), ('Auralis/Resources/BrowseAdapter.js', 'sourcecode.javascript'), ('Auralis/Resources/PlayerAdapter.js', 'sourcecode.javascript'), ('Auralis/Resources/AppIcon.icns', 'image.icns')]:
    resources.append(add(path, '{isa = PBXFileReference; lastKnownFileType = '+kind+'; path = '+quote(path)+'; sourceTree = SOURCE_ROOT;}'))
    resource_builds.append(add('build:'+path, '{isa = PBXBuildFile; fileRef = '+ref(path)+';}'))
test_path = 'Tests/AuralisCoreTests/PlaybackTests.swift'
add(test_path, '{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = '+quote(test_path)+'; sourceTree = SOURCE_ROOT;}')
add('testBuild', '{isa = PBXBuildFile; fileRef = '+ref(test_path)+';}')
add('appProduct', '{isa = PBXFileReference; explicitFileType = wrapper.application; path = Auralis.app; sourceTree = BUILT_PRODUCTS_DIR;}')
add('testProduct', '{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = AuralisTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;}')
add('sourcesGroup', '{isa = PBXGroup; name = Sources; children = '+arr(source_refs)+'; sourceTree = "<group>";}')
add('resourcesGroup', '{isa = PBXGroup; name = Resources; children = '+arr(resources)+'; sourceTree = "<group>";}')
add('productsGroup', '{isa = PBXGroup; name = Products; children = '+arr([ref('appProduct'), ref('testProduct')])+'; sourceTree = "<group>";}')
add('mainGroup', '{isa = PBXGroup; children = '+arr([ref('sourcesGroup'), ref('resourcesGroup'), ref(test_path), ref('productsGroup')])+'; sourceTree = "<group>";}')
add('sources', '{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = '+arr(source_builds)+'; runOnlyForDeploymentPostprocessing = 0;}')
add('resources', '{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = '+arr(resource_builds)+'; runOnlyForDeploymentPostprocessing = 0;}')
add('frameworks', '{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;}')
add('testSources', '{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = '+arr([ref('testBuild')])+'; runOnlyForDeploymentPostprocessing = 0;}')
add('testFrameworks', '{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;}')
add('testProxy', '{isa = PBXContainerItemProxy; containerPortal = '+ref('project')+'; proxyType = 1; remoteGlobalIDString = '+ref('appTarget')+'; remoteInfo = Auralis;}')
add('testDependency', '{isa = PBXTargetDependency; target = '+ref('appTarget')+'; targetProxy = '+ref('testProxy')+';}')
base = {'ARCHS':'arm64','SDKROOT':'macosx','MACOSX_DEPLOYMENT_TARGET':'14.0','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','GCC_C_LANGUAGE_STANDARD':'gnu17','SUPPORTED_PLATFORMS':'macosx'}
for owner in ['project','app','test']:
    for config in ['Debug','Release']:
        settings = dict(base)
        settings['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone' if config == 'Debug' else '-O'
        if owner == 'app':
            settings.update({'PRODUCT_NAME':'Auralis','PRODUCT_BUNDLE_IDENTIFIER':'studio.auralis.signin-spike','INFOPLIST_FILE':'Auralis/Resources/Info.plist','GENERATE_INFOPLIST_FILE':'NO','CODE_SIGN_STYLE':'Manual','CODE_SIGN_IDENTITY':'-','ENABLE_HARDENED_RUNTIME':'YES','ENABLE_APP_SANDBOX':'NO','ENABLE_TESTABILITY':'YES' if config=='Debug' else 'NO','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/../Frameworks','SWIFT_EMIT_LOC_STRINGS':'YES'})
        if owner == 'test':
            settings.update({'PRODUCT_NAME':'AuralisTests','PRODUCT_BUNDLE_IDENTIFIER':'studio.auralis.mac.tests','GENERATE_INFOPLIST_FILE':'YES','CODE_SIGN_STYLE':'Manual','CODE_SIGN_IDENTITY':'-','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/Auralis.app/Contents/MacOS/Auralis','BUNDLE_LOADER':'$(TEST_HOST)','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/../Frameworks @loader_path/../Frameworks'})
        serialized = ' '.join(quote(k)+' = '+quote(v)+';' for k,v in settings.items())
        add(owner+config, '{isa = XCBuildConfiguration; buildSettings = {'+serialized+'}; name = '+config+';}')
    add(owner+'Configs', '{isa = XCConfigurationList; buildConfigurations = '+arr([ref(owner+'Debug'), ref(owner+'Release')])+'; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}')
add('appTarget', '{isa = PBXNativeTarget; buildConfigurationList = '+ref('appConfigs')+'; buildPhases = '+arr([ref('sources'), ref('frameworks'), ref('resources')])+'; buildRules = (); dependencies = (); name = Auralis; productName = Auralis; productReference = '+ref('appProduct')+'; productType = "com.apple.product-type.application";}')
add('testTarget', '{isa = PBXNativeTarget; buildConfigurationList = '+ref('testConfigs')+'; buildPhases = '+arr([ref('testSources'), ref('testFrameworks')])+'; buildRules = (); dependencies = '+arr([ref('testDependency')])+'; name = AuralisTests; productName = AuralisTests; productReference = '+ref('testProduct')+'; productType = "com.apple.product-type.bundle.unit-test";}')
add('project', '{isa = PBXProject; attributes = {LastUpgradeCheck = 1600; BuildIndependentTargetsInParallel = YES;}; buildConfigurationList = '+ref('projectConfigs')+'; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = '+ref('mainGroup')+'; productRefGroup = '+ref('productsGroup')+'; projectDirPath = ""; projectRoot = ""; targets = '+arr([ref('appTarget'), ref('testTarget')])+';}')
(project / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(k+' = '+v+';' for k,v in objects.items())+'\n}; rootObject = '+ref('project')+'; }\n')
scheme_dir = project / 'xcshareddata/xcschemes'
scheme_dir.mkdir(parents=True, exist_ok=True)
app_ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref("appTarget")}" BuildableName="Auralis.app" BlueprintName="Auralis" ReferencedContainer="container:Auralis.xcodeproj"/>'
test_ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref("testTarget")}" BuildableName="AuralisTests.xctest" BlueprintName="AuralisTests" ReferencedContainer="container:Auralis.xcodeproj"/>'
(scheme_dir / 'Auralis.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.7">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{test_ref}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="NO"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>\n''')
print('Generated Auralis.xcodeproj with app, hosted XCTest target, and shared scheme.')
