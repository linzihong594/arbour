#!/usr/bin/env python3
"""Cross-process backup verification against a synthetic library.

Creates a library fixture, runs the signed app in backup-validation mode, then checks the snapshot,
the isolated restore, and the rejection paths without touching any real diary.
"""

from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "build" / "栖木.app" / "Contents" / "MacOS" / "DiaryPreview"


class ValidationFailure(RuntimeError):
    pass


def run(arguments: list[str], *, timeout: int = 180) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(arguments, cwd=ROOT, text=True, capture_output=True, timeout=timeout)
    if result.returncode != 0:
        raise ValidationFailure(
            f"command failed ({result.returncode}): {' '.join(arguments)}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return result


def expect_failure(arguments: list[str], label: str) -> None:
    result = subprocess.run(arguments, cwd=ROOT, text=True, capture_output=True, timeout=180)
    if result.returncode == 0:
        raise ValidationFailure(f"{label}: expected a non-zero exit, got success")
    combined = result.stdout + result.stderr
    if not combined.strip():
        raise ValidationFailure(f"{label}: expected a diagnostic, got empty output")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot_digest(directory: Path) -> dict[str, str]:
    return {
        str(path.relative_to(directory)): sha256(path)
        for path in sorted(directory.rglob("*"))
        if path.is_file()
    }


def main() -> int:
    if not APP.exists():
        print(f"missing signed app: {APP}", file=sys.stderr)
        return 2
    run(["swift", "build", "-c", "release", "--product", "diary-probe"])
    bin_path = Path(
        subprocess.check_output(
            ["swift", "build", "-c", "release", "--show-bin-path"], cwd=ROOT, text=True
        ).strip()
    )
    probe = bin_path / "diary-probe"

    base = Path(tempfile.mkdtemp(prefix="mac-diary-backup-"))
    try:
        library_root = base / "Library"
        entries = library_root / "Entries"
        entries.mkdir(parents=True)
        backup_root = base / "Backup"
        restore_root = base / "Restore"
        report_path = base / "backup-report.json"

        run([str(probe), "backup-fixture", str(entries)])
        source_active = snapshot_digest(entries)

        run(
            [
                str(APP),
                "--library",
                str(entries),
                "--validation-mode",
                "backup",
                "--backup-root",
                str(backup_root),
                "--restore-root",
                str(restore_root),
                "--validation-output",
                str(report_path),
            ],
            timeout=180,
        )

        report = json.loads(report_path.read_text())
        snapshots = sorted((backup_root / "MacDiarySnapshots").glob("snapshot-*"))
        if len(snapshots) != 1:
            raise ValidationFailure(f"expected exactly one snapshot, got {snapshots}")
        snapshot = snapshots[0]

        expected = {
            "manifestEntries": 3,
            "activeEntries": 2,
            "trashedEntries": 1,
            "checksumsVerified": True,
            "completeMarkerExists": True,
            "libraryIndexActive": 2,
            "libraryIndexTrashed": 1,
            "libraryIssues": 0,
            "encryptedContainerByteIdentical": True,
            "trashContainerByteIdentical": True,
            "manifestLeaksBodyText": False,
            "cloudState": "localOnly",
            "localWriteDone": True,
        }
        for key, value in expected.items():
            if report.get(key) != value:
                raise ValidationFailure(f"report[{key!r}] = {report.get(key)!r}, expected {value!r}")

        if snapshot_digest(entries) != source_active:
            raise ValidationFailure("source library changed during backup")
        if sorted(restore_root.glob("*.diary.json")) != sorted(restore_root.glob("*.diary.json")):
            raise ValidationFailure("restore produced an unexpected active file set")
        if len(list(restore_root.glob("*.diary.json"))) != 2:
            raise ValidationFailure("restore did not produce two active diaries")
        if len(list((restore_root / "Trash").glob("*.diary.json"))) != 1:
            raise ValidationFailure("restore did not produce one trashed diary")

        run([str(probe), "library-read", str(restore_root)])

        tampered = base / "Tampered"
        shutil.copytree(snapshot, tampered)
        target = next((tampered / "Entries").glob("*.diary.json"))
        data = bytearray(target.read_bytes())
        data[0] ^= 0x01
        target.write_bytes(data)
        expect_failure([str(probe), "backup-verify", str(tampered)], "tampered snapshot")

        incomplete = base / "Incomplete"
        shutil.copytree(snapshot, incomplete)
        (incomplete / "COMPLETE").unlink()
        expect_failure([str(probe), "backup-verify", str(incomplete)], "missing COMPLETE")

        unexpected = base / "Unexpected"
        shutil.copytree(snapshot, unexpected)
        (unexpected / "Entries" / "ffffffff-ffff-4fff-8fff-ffffffffffff.diary.json").write_text("{}")
        expect_failure([str(probe), "backup-verify", str(unexpected)], "unexpected entry")

        conflict = base / "Conflict"
        conflict.mkdir()
        keep = conflict / "keep.diary.json"
        keep.write_text("keep")
        expect_failure(
            [str(probe), "backup-restore", str(snapshot), str(conflict)], "non-empty target"
        )
        if keep.read_text() != "keep":
            raise ValidationFailure("restore overwrote an existing file")

        result = {
            "report": report,
            "snapshotFiles": len(snapshot_digest(snapshot)),
            "sourceFiles": len(source_active),
            "restoredActive": len(list(restore_root.glob("*.diary.json"))),
            "restoredTrashed": len(list((restore_root / "Trash").glob("*.diary.json"))),
            "failureCases": [
                "tampered checksum",
                "missing COMPLETE marker",
                "unexpected entry",
                "non-empty restore target",
            ],
        }
        print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
        print("PASS: synthetic backup create/verify/restore and rejection paths.")
        return 0
    finally:
        shutil.rmtree(base, ignore_errors=True)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValidationFailure as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
