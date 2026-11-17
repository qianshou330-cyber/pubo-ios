#!/usr/bin/env python3
"""Read-only-to-product, standalone macOS experiment. No acceptance overrides."""
import argparse
import json
import os
from pathlib import Path
import platform
import signal
import subprocess
import threading
import time

PACKAGE = """// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ProbeCore", products: [.library(name: "ProbeCore", targets: ["ProbeCore"])],
 targets: [.target(name: "ProbeCore", path: "Sources/ProbeCore")])
"""
SPEC = """name: WatchProbe
options:
  deploymentTarget:
    macOS: "13.0"
packages:
  ProbeCore:
    path: .
targets:
  WatchProbe:
    type: tool
    platform: macOS
    sources: [App]
    dependencies:
      - package: ProbeCore
"""

def fixture(root):
    (root / "Sources/ProbeCore").mkdir(parents=True)
    (root / "App").mkdir()
    (root / "Package.swift").write_text(PACKAGE)
    (root / "project.yml").write_text(SPEC)
    (root / "Sources/ProbeCore/Value.swift").write_text("public let probeValue = 7\n")
    (root / "App/main.swift").write_text("import ProbeCore\nprint(probeValue)\n")

def command(root, external, derived_inside):
    derived = root / "build/DerivedData" if derived_inside else external / "DerivedData"
    return ["xcodebuild", "-project", str(root / "WatchProbe.xcodeproj"),
            "-scheme", "WatchProbe", "-configuration", "Debug",
            "-destination", "generic/platform=macOS", "-derivedDataPath", str(derived),
            "-clonedSourcePackagesDirPath", str(external / "SourcePackages"),
            "CODE_SIGNING_ALLOWED=NO", "build"]

def run(command, cwd, log_path, budget, pulse_root=None):
    """Time budget includes process exit. Log text cannot change timeout status."""
    started = time.monotonic()
    process = subprocess.Popen(command, cwd=cwd, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True, start_new_session=True)
    stop = threading.Event()
    package_resolved = threading.Event()
    pulse_status = {"marker": "Resolved source packages:", "markerSeen": False,
                    "markerWaitBudget": 30, "skipReason": None}
    markers = []
    write_errors = []
    read_errors = []
    write_count = [0]
    def read():
        with log_path.open("w") as f:
            for line in process.stdout:
                stamp = time.monotonic() - started
                f.write(json.dumps({"seconds": stamp, "line": line.rstrip()}) + "\n")
                f.flush()
                if "Resolved source packages:" in line:
                    pulse_status["markerSeen"] = True
                    package_resolved.set()
                if any(x in line for x in ["Resolve Package Graph", "Resolved source packages:", "packageStructureDidChange",
                                          "processPackageGraphActionsInBackgroundIfNeeded"]):
                    markers.append({"seconds": stamp, "line": line.rstrip()})
    def pulse():
        wait_started = time.monotonic()
        while not package_resolved.is_set():
            if stop.wait(0.1):
                pulse_status["skipReason"] = "process ended before package marker"
                return
            if time.monotonic() - wait_started >= 30:
                pulse_status["skipReason"] = "package marker not observed within 30s"
                return
        if stop.is_set():
            pulse_status["skipReason"] = "process ended before pulses started"
            return
        with log_path.with_suffix(".writes.jsonl").open("w") as f:
            # Same workload and delay in every cell. All paths are synthetic.
            for n in range(20):
                if stop.wait(0.25): break
                directory = pulse_root / ("pulse-%02d" % n)
                directory.mkdir(parents=True)
                path = directory / "generated.swift"
                path.write_text("// synthetic generated artifact\n")
                write_count[0] += 1
                f.write(json.dumps({"seconds": time.monotonic()-started,
                                    "path": str(path), "operation": "create"})+"\n")
                f.flush()
    def safe_read():
        try: read()
        except Exception as error: read_errors.append(repr(error))
    reader = threading.Thread(target=safe_read, daemon=True); reader.start()
    def safe_pulse():
        try: pulse()
        except Exception as error: write_errors.append(repr(error))
    writer = threading.Thread(target=safe_pulse, daemon=True) if pulse_root else None
    if writer: writer.start()
    timed_out = False
    try:
        process.wait(timeout=budget)
    except subprocess.TimeoutExpired:
        timed_out = True
        os.killpg(process.pid, signal.SIGTERM)
        try: process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL); process.wait(timeout=5)
    finally:
        stop.set()
        if writer: writer.join(timeout=2)
        reader.join(timeout=5)
        if not reader.is_alive(): process.stdout.close()
    return {"command": command, "budget": budget, "elapsed": time.monotonic()-started,
            "returncode": process.returncode, "timedOut": timed_out, "markers": markers,
            "readerFinished": not reader.is_alive(), "readErrors": read_errors,
            "writerFinished": writer is None or not writer.is_alive(), "writeCount": write_count[0],
            "writeErrors": write_errors, "pulseStatus": pulse_status}

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--budget", type=int, default=120)
    p.add_argument("--reverse", action="store_true")
    args = p.parse_args()
    if platform.system() != "Darwin": p.error("Actual experiment requires macOS/Xcode")
    if args.budget < 1: p.error("budget must be positive")
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=False)
    metadata = {"platform": platform.platform(), "budgetPerProcess": args.budget}
    for name, cmd in [("xcode", ["xcodebuild", "-version"]), ("generator", ["xcodegen", "--version"])]:
        metadata[name] = subprocess.run(cmd, capture_output=True, text=True, timeout=30, check=True).stdout
    (root/"environment.json").write_text(json.dumps(metadata, indent=2))
    cells = [(d,w) for d in (False,True) for w in (False,True)]
    if args.reverse: cells.reverse()
    results = []
    for derived_inside, writes_inside in cells:
        name = "derived-%s_writes-%s" % ("inside" if derived_inside else "outside",
                                       "inside" if writes_inside else "outside")
        cell = root/name; cell.mkdir()
        package = cell/"package"; external = cell/"external"; external.mkdir()
        fixture(package)
        subprocess.run(["xcodegen", "generate"], cwd=package, check=True, timeout=60)
        cmd = command(package, external, derived_inside)
        warm = run(cmd, package, cell/"warm.jsonl", args.budget)
        record = {"cell":name, "warm":warm}
        if warm["returncode"] == 0 and not warm["timedOut"]:
            # Identical invalidation before measurement, outside the timed window.
            with (package/"App/main.swift").open("a") as f: f.write("// measured rebuild\n")
            pulse_root = package/"build/pulses" if writes_inside else external/"pulses"
            record["measured"] = run(cmd, package, cell/"measured.jsonl",
                                     args.budget, pulse_root)
        else:
            record["measured"] = {"notRun":"warm build did not complete successfully"}
        results.append(record)
        (root/"summary.json").write_text(json.dumps(results, indent=2))
    print(root/"summary.json")

if __name__ == "__main__": main()
