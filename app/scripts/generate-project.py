#!/usr/bin/env python3
"""Recreate the dependency-free Xcode project after adding Swift source files."""
from pathlib import Path
import hashlib

root = Path(__file__).resolve().parents[1]
project = root / 'Audience.xcodeproj'
project.mkdir(exist_ok=True)
def uid(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def quoted(value): return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'
objects = []
def add(name, body):
    objects.append(f'{uid(name)} = {{ {body} }};')
    return uid(name)
files = sorted(root.glob('Sources/**/*.swift'))
refs, builds = [], []
for file in files:
    path = file.relative_to(root).as_posix()
    refs.append(add('ref:' + path, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quoted(path)}; sourceTree = "<group>";'))
    builds.append(add('build:' + path, f'isa = PBXBuildFile; fileRef = {refs[-1]};'))
icon = add('icon', 'isa = PBXFileReference; lastKnownFileType = image.icns; path = Resources/AppIcon.icns; sourceTree = "<group>";')
info = add('info', 'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Resources/Info.plist; sourceTree = "<group>";')
icon_build = add('iconBuild', f'isa = PBXBuildFile; fileRef = {icon};')
product = add('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = Audience.app; sourceTree = BUILT_PRODUCTS_DIR;')
products = add('products', f'isa = PBXGroup; name = Products; children = ({product},); sourceTree = "<group>";')
main = add('main', f'isa = PBXGroup; children = ({",".join(refs + [icon, info, products])},); sourceTree = "<group>";')
sources = add('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)},); runOnlyForDeploymentPostprocessing = 0;')
resources = add('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({icon_build},); runOnlyForDeploymentPostprocessing = 0;')
frameworks = add('frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
project_configs, target_configs = [], []
for config in ['Debug', 'Release']:
    debug = config == 'Debug'
    project_configs.append(add('project' + config, f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 26.0; SWIFT_VERSION = 6.0; CLANG_ENABLE_MODULES = YES; SWIFT_OPTIMIZATION_LEVEL = {quoted("-Onone" if debug else "-O")}; SWIFT_ACTIVE_COMPILATION_CONDITIONS = {quoted("DEBUG" if debug else "")}; DEBUG_INFORMATION_FORMAT = {quoted("dwarf" if debug else "dwarf-with-dsym")}; }};'))
    target_configs.append(add('target' + config, f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ PRODUCT_NAME = Audience; PRODUCT_BUNDLE_IDENTIFIER = fr.audience.native; INFOPLIST_FILE = Resources/Info.plist; GENERATE_INFOPLIST_FILE = NO; CODE_SIGN_STYLE = Automatic; CODE_SIGN_IDENTITY = "-"; ENABLE_HARDENED_RUNTIME = YES; ENABLE_APP_SANDBOX = NO; SWIFT_EMIT_LOC_STRINGS = YES; ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = ""; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks"; }};'))
project_list = add('projectConfigs', f'isa = XCConfigurationList; buildConfigurations = ({",".join(project_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target_list = add('targetConfigs', f'isa = XCConfigurationList; buildConfigurations = ({",".join(target_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target = add('target', f'isa = PBXNativeTarget; buildConfigurationList = {target_list}; buildPhases = ({sources},{frameworks},{resources},); buildRules = (); dependencies = (); name = Audience; productName = Audience; productReference = {product}; productType = "com.apple.product-type.application";')
project_id = add('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2700; }}; buildConfigurationList = {project_list}; compatibilityVersion = "Xcode 14.0"; developmentRegion = fr; hasScannedForEncodings = 0; knownRegions = (fr,Base,); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target},);')
(project / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {project_id}; }}\n')
schemes = project / 'xcshareddata/xcschemes'
schemes.mkdir(parents=True, exist_ok=True)
ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Audience.app" BlueprintName="Audience" ReferencedContainer="container:Audience.xcodeproj"/>'
(schemes / 'Audience.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print(project)
