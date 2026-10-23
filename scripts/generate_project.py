#!/usr/bin/env python3
"""Generate the checked-in two-target Xcode project with no external dependencies."""
import hashlib
import json
from pathlib import Path

from signing_config import SETTING_NAMES, variable

ROOT = Path(__file__).resolve().parents[1]
objects = {}

def ident(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def obj(key_name, **fields):
    key = ident(key_name)
    objects[key] = fields
    return key

def render(value):
    if isinstance(value, dict):
        return "{ " + " ".join(f"{k} = {render(v)};" for k, v in value.items()) + " }"
    if isinstance(value, list):
        return "( " + ", ".join(render(v) for v in value) + ("," if value else "") + " )"
    return json.dumps(str(value))

products = []
groups = []
targets = []
signing_config = obj("signing:config", isa="PBXFileReference", lastKnownFileType="text.xcconfig",
                     path="Config/Signing.xcconfig", sourceTree="SOURCE_ROOT")
shared = sorted((ROOT / "Shared").glob("*.swift"))
for folder, name, product, sdk in [
    ("iPad", "StyleusPad", "Styleus iPad", "iphoneos"),
    ("Mac", "StyleusMac", "Styleus Mac", "macosx")
]:
    files = shared + sorted((ROOT / folder).glob("*.swift"))
    refs, buildrefs, resources = [], [], []
    for path in files:
        relative = path.relative_to(ROOT).as_posix()
        reference = obj("file:" + relative, isa="PBXFileReference", lastKnownFileType="sourcecode.swift", path=relative, sourceTree="SOURCE_ROOT")
        if path.parent.name != "Shared":
            refs.append(reference)
        buildrefs.append(obj(name + ":build:" + relative, isa="PBXBuildFile", fileRef=reference))
    for path in sorted((ROOT / folder).glob("*.xcassets")):
        relative = path.relative_to(ROOT).as_posix()
        reference = obj("file:" + relative, isa="PBXFileReference", lastKnownFileType="folder.assetcatalog", path=relative, sourceTree="SOURCE_ROOT")
        refs.append(reference)
        resources.append(obj(name + ":resource:" + relative, isa="PBXBuildFile", fileRef=reference))
    refs.append(obj(name + ":plist", isa="PBXFileReference", lastKnownFileType="text.plist.xml", path=f"{folder}/Info.plist", sourceTree="SOURCE_ROOT"))
    groups.append(obj(name + ":group", isa="PBXGroup", name=name, children=refs, sourceTree="<group>"))
    product_ref = obj(name + ":product", isa="PBXFileReference", explicitFileType="wrapper.application", path=product + ".app", sourceTree="BUILT_PRODUCTS_DIR")
    products.append(product_ref)
    phases = [obj(name + ":sources", isa="PBXSourcesBuildPhase", buildActionMask="2147483647", files=buildrefs, runOnlyForDeploymentPostprocessing="0"),
              obj(name + ":frameworks", isa="PBXFrameworksBuildPhase", buildActionMask="2147483647", files=[], runOnlyForDeploymentPostprocessing="0"),
              obj(name + ":resources", isa="PBXResourcesBuildPhase", buildActionMask="2147483647", files=resources, runOnlyForDeploymentPostprocessing="0")]
    configs = []
    for config in ["Debug", "Release"]:
        settings = dict(SWIFT_VERSION="5.0", PRODUCT_NAME=product,
                        SDKROOT=sdk, INFOPLIST_FILE=f"{folder}/Info.plist", GENERATE_INFOPLIST_FILE="NO",
                        SWIFT_OPTIMIZATION_LEVEL="-Onone" if config == "Debug" else "-O",
                        SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG" if config == "Debug" else "",
                        ENABLE_USER_SCRIPT_SANDBOXING="YES", CLANG_ENABLE_MODULES="YES",
                        ASSETCATALOG_COMPILER_APPICON_NAME="AppIcon",
                        LD_RUNPATH_SEARCH_PATHS="$(inherited) @executable_path/Frameworks" if folder == "iPad" else "$(inherited) @executable_path/../Frameworks")
        if folder == "iPad":
            settings.update(IPHONEOS_DEPLOYMENT_TARGET="17.0", TARGETED_DEVICE_FAMILY="2",
                            SUPPORTED_PLATFORMS="iphoneos iphonesimulator", SUPPORTS_MACCATALYST="NO",
                            SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD="NO")
        else:
            settings.update(MACOSX_DEPLOYMENT_TARGET="14.0", SUPPORTED_PLATFORMS="macosx",
                            ENABLE_APP_SANDBOX="NO", COMBINE_HIDPI_IMAGES="YES")
        # Public references stay deterministic; personal values live only in Local.xcconfig.
        settings.update({key: "$(" + variable(name, key) + ")" for key in SETTING_NAMES})
        configs.append(obj(name + ":" + config, isa="XCBuildConfiguration", name=config,
                           baseConfigurationReference=signing_config, buildSettings=settings))
    configlist = obj(name + ":configs", isa="XCConfigurationList", buildConfigurations=configs, defaultConfigurationIsVisible="0", defaultConfigurationName="Debug")
    target = obj(name, isa="PBXNativeTarget", name=name, productName=product, productReference=product_ref,
                 productType="com.apple.product-type.application", buildConfigurationList=configlist,
                 buildPhases=phases, buildRules=[], dependencies=[])
    targets.append(target)
    scheme = ROOT / "Styleus.xcodeproj/xcshareddata/xcschemes" / (name + ".xcscheme")
    scheme.parent.mkdir(parents=True, exist_ok=True)
    reference_xml = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{product}.app" BlueprintName="{name}" ReferencedContainer="container:Styleus.xcodeproj"/>'
    scheme.write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2660" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference_xml}</BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"/>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">{reference_xml}</BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release"><BuildableProductRunnable runnableDebuggingMode="0">{reference_xml}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')

groups.insert(0, obj("shared", isa="PBXGroup", name="Shared", children=[ident("file:" + p.relative_to(ROOT).as_posix()) for p in shared], sourceTree="<group>"))
groups.append(obj("config:group", isa="PBXGroup", name="Config", children=[signing_config], sourceTree="<group>"))
products_group = obj("products", isa="PBXGroup", name="Products", children=products, sourceTree="<group>")
main_group = obj("main", isa="PBXGroup", children=groups + [products_group], sourceTree="<group>")
project_configs = [obj("project:" + name, isa="XCBuildConfiguration", name=name, buildSettings={"CLANG_ENABLE_MODULES": "YES"}) for name in ["Debug", "Release"]]
project_list = obj("project:configs", isa="XCConfigurationList", buildConfigurations=project_configs, defaultConfigurationIsVisible="0", defaultConfigurationName="Debug")
project = obj("project", isa="PBXProject", attributes={"LastUpgradeCheck": "2660"}, buildConfigurationList=project_list,
              compatibilityVersion="Xcode 14.0", developmentRegion="en", knownRegions=["en", "Base"], mainGroup=main_group,
              productRefGroup=products_group, projectDirPath="", projectRoot="", targets=targets)
contents = "// !$*UTF8*$!\n" + render(dict(archiveVersion="1", classes={}, objectVersion="56", objects=objects, rootObject=project)) + "\n"
(ROOT / "Styleus.xcodeproj/project.pbxproj").write_text(contents)
print("Generated Styleus.xcodeproj (StyleusPad + StyleusMac)")
