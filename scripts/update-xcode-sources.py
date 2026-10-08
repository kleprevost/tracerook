#!/usr/bin/env python3
"""Keep the checked-in native Xcode targets aligned with Swift package executable sources."""
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "TraceRook.xcodeproj/project.pbxproj"
project = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(PROJECT)]))
objects = project["objects"]
objects[project["rootObject"]]["compatibilityVersion"] = "Xcode 15.0"
def ident(key):
    return hashlib.sha256(key.encode()).hexdigest()[:24].upper()
for target, folder in [("TraceRook", "App"), ("TraceRookAgent", "Agent"), ("tracerook-hook", "HookCLI")]:
    refs, builds = [], []
    for source in sorted((ROOT / folder).rglob("*.swift")):
        path = str(source.relative_to(ROOT))
        ref, build = ident(path), ident("build:" + path)
        objects[ref] = dict(isa="PBXFileReference", lastKnownFileType="sourcecode.swift", path=path, sourceTree="SOURCE_ROOT")
        objects[build] = dict(isa="PBXBuildFile", fileRef=ref)
        refs.append(ref); builds.append(build)
    objects[ident("group:" + folder)]["children"] = refs
    objects[ident("sources:" + target)]["files"] = builds
icon_ref, icon_build, icon_phase = ident("app-icon"), ident("app-icon-build"), ident("app-resources")
objects[icon_ref] = dict(isa="PBXFileReference", lastKnownFileType="image.icns", path="Resources/TraceRook.icns", sourceTree="SOURCE_ROOT")
objects[icon_build] = dict(isa="PBXBuildFile", fileRef=icon_ref)
objects[icon_phase] = dict(isa="PBXResourcesBuildPhase", buildActionMask="2147483647", files=[icon_build], runOnlyForDeploymentPostprocessing="0")
app_target = objects[ident("target:TraceRook")]
if icon_phase not in app_target["buildPhases"]: app_target["buildPhases"].append(icon_phase)
app_group = objects[ident("group:App")]
if icon_ref not in app_group["children"]: app_group["children"].append(icon_ref)
def encode(value, indent=0):
    if isinstance(value, dict):
        return "{\n" + "".join("\t" * (indent + 1) + json.dumps(k) + " = " + encode(v, indent + 1) + ";\n" for k, v in value.items()) + "\t" * indent + "}"
    if isinstance(value, list):
        return "(" + ", ".join(encode(v, indent) for v in value) + ("," if value else "") + ")"
    return json.dumps(str(value))
PROJECT.write_text("// !$*UTF8*$!\n" + encode(project) + "\n")
