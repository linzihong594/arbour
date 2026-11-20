#!/usr/bin/env python3
"""Build the local preview without installing or modifying another application."""

import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess
import signing


ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "build" / "栖木.app"


def run(*arguments: str) -> None:
    subprocess.run(arguments, cwd=ROOT, check=True)


def test(test_filter: str | None = None) -> None:
    arguments = ["swift", "test", "--disable-xctest"]
    compiler = Path(subprocess.check_output(["xcrun", "--find", "swiftc"], text=True).strip())
    testing_plugin = compiler.parent.parent / "lib/swift/host/plugins/testing/libTestingMacros.dylib"
    # Some CLT releases bundle Swift Testing but do not discover its macro plugin.
    if testing_plugin.exists():
        arguments += ["-Xswiftc", "-load-plugin-library", "-Xswiftc", str(testing_plugin)]
    if test_filter:
        arguments += ["--filter", test_filter]
    run(*arguments)


def build(identity: str | None = None, profile: Path | None = None, bundle_id: str | None = None) -> Path:
    info = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
    if bundle_id:
        info["CFBundleIdentifier"] = bundle_id
    assets = signing.prepare(identity, profile, info["CFBundleIdentifier"], ROOT / "build/signing")
    run("swift", "build", "-c", "release", "--product", "DiaryPreview")
    output = subprocess.check_output(
        ["swift", "build", "-c", "release", "--show-bin-path"], cwd=ROOT, text=True
    ).strip()

    # Replace only this project's generated app; source and user data remain separate.
    if APP.exists():
        shutil.rmtree(APP)
    contents = APP / "Contents"
    executable = contents / "MacOS"
    resources = contents / "Resources"
    executable.mkdir(parents=True)
    resources.mkdir()
    shutil.copy2(Path(output) / "DiaryPreview", executable / "DiaryPreview")
    (contents / "Info.plist").write_bytes(plistlib.dumps(info))

    iconset = ROOT / "build" / "AppIcon.iconset"
    run("xcrun", "swift", str(ROOT / "scripts" / "draw_icon.swift"), str(iconset))
    run("iconutil", "-c", "icns", str(iconset), "-o", str(resources / "AppIcon.icns"))

    license_path = ROOT / ".build" / "checkouts" / "swift-markdown-engine" / "LICENSE"
    shutil.copy2(license_path, resources / "MarkdownEngine-LICENSE.txt")
    shutil.copy2(ROOT / "docs" / "THIRD_PARTY.md", resources / "Acknowledgements.md")
    signing.sign(APP, assets)
    print(f"{'Apple identity' if assets else 'Local ad-hoc'} signed preview: {APP}")
    return APP


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["build", "run", "test", "demo"])
    parser.add_argument("--identity", help="本机 Apple Development / Developer ID 证书名称或 SHA-1")
    parser.add_argument("--profile", type=Path, help="匹配的 macOS provisioning profile")
    parser.add_argument("--bundle-id", help="与描述文件匹配的已注册 Bundle ID")
    parser.add_argument("--filter", help="只执行匹配的 Swift Testing 测试")
    args = parser.parse_args()
    if args.action == "test":
        test(args.filter)
    else:
        app = build(args.identity, args.profile, args.bundle_id)
        if args.action == "run":
            run("open", str(app))
        elif args.action == "demo":
            run("open", "-n", str(app), "--args", "--demo")


if __name__ == "__main__":
    main()
