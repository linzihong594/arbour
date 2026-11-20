#!/usr/bin/env python3
"""Prepare a separately identified, synthetic-only app for native UI checks."""

import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
from tempfile import mkdtemp


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "build/validation"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--width", type=int, choices=[820, 1080], default=1080)
    parser.add_argument("--long-title", action="store_true")
    parser.add_argument("--appearance", choices=["light", "dark"], default="light")
    args = parser.parse_args()
    app = OUTPUT / "日记验证.app"
    # GUI launches must not need access to Documents just to run synthetic checks.
    library = Path(mkdtemp(prefix="mac-diary-ui-")) / "Entries"
    if app.exists():
        shutil.rmtree(app)
    shutil.copytree(ROOT / "build/栖木.app", app)
    info = app / "Contents/Info.plist"
    data = plistlib.loads(info.read_bytes())
    data.update({
        "CFBundleIdentifier": "local.mac-diary.validation",
        "CFBundleName": "日记验证",
        "CFBundleDisplayName": "日记验证",
        "MacDiaryValidationLibrary": str(library),
        "MacDiaryValidationAppearance": args.appearance,
        "MacDiaryValidationWindowWidth": args.width,
    })
    info.write_bytes(plistlib.dumps(data))
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
    binary_dir = Path(subprocess.check_output(
        ["swift", "build", "-c", "release", "--show-bin-path"], cwd=ROOT, text=True
    ).strip())
    subprocess.run([str(binary_dir / "diary-probe"), "library-write", str(library)], check=True)
    if args.long_title:
        entry = library / "10101010-1010-4010-8010-101010101010.diary.json"
        document = json.loads(entry.read_text())
        document["metadata"]["title"] = "用于窄窗口回归的合成长标题🌿" * 20
        entry.write_text(json.dumps(document, ensure_ascii=False))
    fixture = {"app": str(app), "library": str(library), "bundle_id": data["CFBundleIdentifier"]}
    (OUTPUT / "ui-fixture.json").write_text(json.dumps(fixture, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(fixture, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
