#!/usr/bin/env python3
"""Measure the Release build with an isolated library of synthetic diaries."""

import argparse
import json
from pathlib import Path
import statistics
import subprocess
from tempfile import TemporaryDirectory
import time


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "build/validation"
APP = ROOT / "build/栖木.app"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", choices=["m2", "security"], default="m2")
    args = parser.parse_args()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    subprocess.run(["python3", "scripts/manage.py", "build"], cwd=ROOT, check=True)
    for product in ["diary-probe", "editor-probe"]:
        subprocess.run(["swift", "build", "-c", "release", "--product", product], cwd=ROOT, check=True)
    binary_dir = Path(subprocess.check_output(
        ["swift", "build", "-c", "release", "--show-bin-path"], cwd=ROOT, text=True
    ).strip())
    editor_report = OUTPUT / f"{args.label}-editor.json"
    subprocess.run([str(binary_dir / "editor-probe"), str(editor_report)], cwd=ROOT, check=True)
    launches = []
    application_log = OUTPUT / f"{args.label}-application.log"
    application_log.write_text("")
    with TemporaryDirectory(prefix="mac-diary-benchmark-") as temporary:
        directory = Path(temporary)
        library = directory / "Library.noindex"
        subprocess.run([str(binary_dir / "diary-probe"), "seed-library", str(library), "1000"], check=True)
        for number in range(5):
            report, latency = measure_application(
                library, directory / f"startup-{number}.json", "startup", application_log)
            assert report["entries"] == 1000
            launches.append(latency)
            print(f"Startup {number + 1}/5: {latency:.3f}s", flush=True)
        print("Measuring application physical footprint and CPU over 60 idle seconds…", flush=True)
        idle, _ = measure_application(library, directory / "idle.json", "idle", application_log)
    bundle_bytes = sum(path.stat().st_size for path in APP.rglob("*") if path.is_file())
    result = {
        "dataset": "1000 synthetic on-disk diaries; newest document has 10,000 characters",
        "app_logical_bytes": bundle_bytes,
        "startup_seconds": launches,
        "startup_median_seconds": statistics.median(launches),
        "startup_maximum_seconds": max(launches),
        "startup_scope": "fresh process to native window content layout and readiness report, includes 50ms settle and <=20ms polling; OS caches not purged",
        "idle": idle,
        "editor": json.loads(editor_report.read_text()),
        "reentrant_warning_present": "reentrant" in application_log.read_text(),
    }
    report_path = OUTPUT / f"{args.label}-performance.json"
    report_path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    print(f"Evidence: {report_path}")
    if result["reentrant_warning_present"]:
        raise RuntimeError("NSTableView reentrant warning regressed")


def measure_application(library: Path, report_path: Path, mode: str, log_path: Path) -> tuple[dict, float]:
    ready_path = report_path.with_suffix(report_path.suffix + ".ready.json")
    command = [str(APP / "Contents/MacOS/DiaryPreview"), "--library", str(library),
               "--validation-output", str(report_path), "--validation-mode", mode]
    started = time.monotonic()
    with log_path.open("a") as log:
        process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=log)
        try:
            deadline = started + 20
            while not ready_path.exists():
                if process.poll() is not None:
                    raise RuntimeError(f"Validation process exited before readiness: {process.returncode}")
                if time.monotonic() > deadline:
                    raise TimeoutError("Application did not become ready")
                time.sleep(0.02)
            latency = time.monotonic() - started
            readiness = json.loads(ready_path.read_text())
            assert readiness["entries"] == 1000 and readiness["hasEditor"]
            process.wait(timeout=80 if mode == "idle" else 20)
            if process.returncode:
                raise RuntimeError(f"Validation process failed: {process.returncode}")
            return json.loads(report_path.read_text()), latency
        finally:
            # Only this script's own synthetic validation process is eligible for cleanup.
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)


if __name__ == "__main__":
    main()
