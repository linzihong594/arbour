#!/usr/bin/env python3
"""Validate live-window privacy with a generated library and a process-local lock event."""

import json
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "build/validation"


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    subprocess.run(["python3", "scripts/manage.py", "build"], cwd=ROOT, check=True)
    subprocess.run(["swift", "build", "-c", "release", "--product", "diary-probe"], cwd=ROOT, check=True)
    binary_dir = Path(subprocess.check_output(
        ["swift", "build", "-c", "release", "--show-bin-path"], cwd=ROOT, text=True
    ).strip())
    with TemporaryDirectory(prefix="mac-diary-privacy-") as temporary:
        folder = Path(temporary)
        library = folder / "Entries"
        report = folder / "privacy.json"
        subprocess.run([str(binary_dir / "diary-probe"), "library-write", str(library)], check=True)
        result = subprocess.run([
            str(ROOT / "build/栖木.app/Contents/MacOS/DiaryPreview"),
            "--library", str(library), "--validation-mode", "privacy",
            "--validation-output", str(report), "--appearance", "light",
        ], cwd=ROOT, capture_output=True, text=True, timeout=25)
        (OUTPUT / "security-window.log").write_text(result.stdout + result.stderr)
        result.check_returncode()
        data = json.loads(report.read_text())
        assert not data["normal_library_accessed"]
        assert not (folder / "refused.md").exists()
        marker = "SEC005-NATIVE-合成补记".encode()
        assert not any(marker in p.read_bytes() for p in library.rglob("*") if p.is_file())
        reopened = subprocess.run([
            str(binary_dir / "diary-probe"), "privacy-read", str(library)
        ], check=True, text=True, capture_output=True)
        print(reopened.stdout.strip())
        data["fresh_process_recovery"] = True
        data["private_body_absent_from_library_files"] = True
        data["refused_export_created_no_file"] = True
        data["startup_reentrant_warning"] = "reentrant" in result.stderr
        assert not data["startup_reentrant_warning"]
        (OUTPUT / "security-window.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
        print(json.dumps(data, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
