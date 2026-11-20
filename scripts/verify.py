#!/usr/bin/env python3
"""Run isolated cross-process probes using synthetic data only."""

import json
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory


ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "build" / "validation" / "process-probes.json"


def main() -> None:
    subprocess.run(["swift", "build", "--product", "diary-probe"], cwd=ROOT, check=True)
    binary_dir = subprocess.check_output(
        ["swift", "build", "--show-bin-path"], cwd=ROOT, text=True
    ).strip()
    binary = Path(binary_dir) / "diary-probe"
    results = []

    def probe(*arguments: str) -> None:
        result = subprocess.run(
            [str(binary), *arguments], cwd=ROOT, check=True, text=True, capture_output=True
        )
        results.append({"operation": arguments[0], "output": result.stdout.strip()})
        print(result.stdout.strip())

    with TemporaryDirectory(prefix="mac-diary-verify-") as temporary:
        directory = Path(temporary)
        encrypted = directory / "synthetic.diary.json"
        backup = directory / "backup"
        backup.mkdir()
        bookmark = directory / "directory.bookmark"

        probe("crypto-write", str(encrypted))
        probe("crypto-read", str(encrypted))
        library = directory / "library"
        probe("library-write", str(library))
        probe("library-read", str(library))
        originals = {p.name: p.read_bytes() for p in library.glob("*.diary.json")}
        probe("library-trash", str(library))
        assert not list(library.glob("*.diary.json"))
        assert {p.name: p.read_bytes() for p in (library / "Trash").glob("*.diary.json")} == originals
        probe("library-restore", str(library))
        assert {p.name: p.read_bytes() for p in library.glob("*.diary.json")} == originals
        assert not list((library / "Trash").glob("*.diary.json"))
        probe("library-read", str(library))
        results.append({"operation": "trash-restore-byte-identity", "passed": True})
        probe("bookmark-write", str(backup), str(bookmark))
        probe("bookmark-read", str(bookmark))
        if list(backup.iterdir()):
            raise RuntimeError("Directory probe left temporary files behind")

    probe("capabilities")
    probe("keychain-configuration")
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n")
    print(f"Evidence: {REPORT}")


if __name__ == "__main__":
    main()
