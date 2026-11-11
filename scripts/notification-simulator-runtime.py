"""Pin both notification comparison devices to the runtime used for build 134."""
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess


def inventory(category):
    output = subprocess.check_output(["xcrun", "simctl", "list", category, "--json"])
    return json.loads(output)[category]


runtime_id = "com.apple.CoreSimulator.SimRuntime.iOS-26-0"
runtime = next((r for r in inventory("runtimes") if r["identifier"] == runtime_id and r.get("isAvailable")), None)
if not runtime:
    architecture = "arm64" if platform.machine() == "arm64" else "universal"
    subprocess.run(["xcodebuild", "-downloadPlatform", "iOS", "-architectureVariant", architecture], check=True, timeout=1400)
    runtime = next(r for r in inventory("runtimes") if r["identifier"] == runtime_id and r.get("isAvailable"))
assert (runtime["version"], runtime["buildversion"]) == ("26.0.1", "23A8464"), runtime
devices = inventory("devices").get(runtime_id, [])
for name, model in [("iPhone 17 Pro Max", "iPhone-17-Pro-Max"), ("iPhone SE (3rd generation)", "iPhone-SE-3rd-generation")]:
    if not any(d["name"] == name and d.get("isAvailable") for d in devices):
        subprocess.run(["xcrun", "simctl", "create", name, "com.apple.CoreSimulator.SimDeviceType." + model, runtime_id], check=True, timeout=60)
commit = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
assert commit == os.environ["GITHUB_SHA"]
fixture = Path("App/Resources/NotificationVisualCases.json")
packaged = os.environ.get("PUBO_PACKAGED_COMMIT") or commit
changed = subprocess.check_output(["git", "diff", "--name-only", packaged, commit], text=True).splitlines()
allowed_checks = {".github/workflows/notification-alignment.yml", "scripts/local-timeline-tests.py",
                  "scripts/notification-simulator-runtime.py", "scripts/check-notification-badge.swift"}
assert all(p.startswith("UITests/") or p in allowed_checks for p in changed), changed
product_trees = {}
for path in ["App", "Sources", "project.yml", "Package.swift", "scripts/package-device.py", "scripts/brand-assets.swift"]:
    blob = subprocess.check_output(["git", "rev-parse", packaged + ":" + path], text=True).strip()
    assert blob == subprocess.check_output(["git", "rev-parse", commit + ":" + path], text=True).strip()
    product_trees[path] = blob
manifest = {"productCommit": packaged, "testCommit": commit, "testOnlyChanges": changed, "productTrees": product_trees,
            "fixtureSHA256": hashlib.sha256(fixture.read_bytes()).hexdigest(),
            "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
            "runtime": runtime["version"], "runtimeBuild": runtime["buildversion"], "runnerArchitecture": platform.machine()}
Path("build").mkdir(exist_ok=True)
Path("build/integration-product-source.json").write_text(json.dumps(manifest, indent=2) + "\n")
