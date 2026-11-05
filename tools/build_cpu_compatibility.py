#!/usr/bin/env python3
"""Build a locally signed CPU compatibility app without installing it."""
import argparse
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=root / "build/Glance.app")
    args = parser.parse_args()
    output = args.output.expanduser().resolve()
    if output.exists():
        parser.error(f"Output already exists: {output}. Choose a new output path.")
    derived = root / "build/CPUCompatibilityDerivedData"
    run("xcodebuild", "-project", root / "glance.xcodeproj", "-scheme", "glance",
        "-configuration", "Release", "-derivedDataPath", derived,
        "-destination", "platform=macOS,arch=x86_64", "CODE_SIGNING_ALLOWED=NO",
        "CODE_SIGNING_REQUIRED=NO", "DEVELOPMENT_TEAM=", "ONLY_ACTIVE_ARCH=YES", "ARCHS=x86_64", "build")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="glance-cpu-", dir=output.parent) as temporary:
        temporary = Path(temporary)
        app = temporary / "Glance.app"
        shutil.copytree(derived / "Build/Products/Release/glance.app", app, symlinks=True)
        resources = app / "Contents/Resources"
        resources.mkdir(exist_ok=True)
        if not (resources / "ArcFace.mlmodelc").exists():
            compiled = temporary / "compiled"
            compiled.mkdir()
            run("xcrun", "coremlcompiler", "compile", root / "glance/Models/ArcFace.mlpackage", compiled)
            shutil.copytree(compiled / "ArcFace.mlmodelc", resources / "ArcFace.mlmodelc", symlinks=True)
        iconset = temporary / "GlanceIcon.iconset"
        iconset.mkdir()
        source_icon = root / "glance/Assets.xcassets/appicon.imageset/appicon.png"
        for size in (16, 32, 128, 256, 512):
            for factor in (1, 2):
                suffix = "@2x" if factor == 2 else ""
                run("sips", "-z", size * factor, size * factor, source_icon,
                    "--out", iconset / f"icon_{size}x{size}{suffix}.png")
        run("iconutil", "-c", "icns", iconset, "-o", resources / "GlanceIcon.icns")
        info_path = app / "Contents/Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info.update(GlanceCPUCompatibility=True, CFBundleVersion="4.7",
                    CFBundleIconFile="GlanceIcon.icns", SUEnableAutomaticChecks=False,
                    SUAutomaticallyUpdate=False)
        info.pop("CFBundleIconName", None)
        info_path.write_bytes(plistlib.dumps(info))
        run("codesign", "--force", "--deep", "--sign", "-", app / "Contents/Frameworks/Sparkle.framework")
        run("codesign", "--force", "--sign", "-", "--identifier", "com.jonathan.glance",
            "--entitlements", root / "tools/CPUCompatibility.entitlements", app)
        run("codesign", "--verify", "--deep", "--strict", app)
        app.rename(output)
    print(f"Built {output}. Installation and macOS permissions are separate user actions.")


if __name__ == "__main__":
    main()
