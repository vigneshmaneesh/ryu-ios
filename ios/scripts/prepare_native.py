"""Materialize a checksum-pinned official iOS MoltenVK framework and headers."""
import hashlib
import argparse
import json
from pathlib import Path
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
lock = json.loads((ROOT / "ios/native-dependencies.lock.json").read_text())["moltenVk"]
output = ROOT / "ios/build/native-dependencies"
output.mkdir(parents=True, exist_ok=True)
archive = ROOT / f'ios/build/MoltenVK-ios-{lock["version"]}.tar'
if not archive.exists():
    request = urllib.request.Request(lock["url"], headers={"User-Agent": "ryu-ios-build/1"})
    with urllib.request.urlopen(request, timeout=120) as response, archive.open("wb") as target:
        while block := response.read(1024 * 1024):
            target.write(block)
actual = hashlib.sha256(archive.read_bytes()).hexdigest()
if actual != lock["sha256"]:
    raise RuntimeError(f"Native dependency checksum mismatch: {archive.name}")
with tarfile.open(archive) as tar:
    prefixes = (lock["framework"] + "/", lock["headers"] + "/")
    members = [m for m in tar if m.name == "MoltenVK/LICENSE" or m.name.startswith(prefixes)]
    tar.extractall(output, members=members, filter="data")
assert (output / lock["framework"] / "MoltenVK").is_file()
assert (output / lock["headers"] / "vulkan/vulkan.h").is_file()
print(f'MoltenVK {lock["version"]}: official iOS ARM64 framework checksum verified.')

parser = argparse.ArgumentParser()
parser.add_argument("--validation", action="store_true", help="Also materialize macOS and iOS simulator frameworks.")
args = parser.parse_args()
if args.validation:
    validation = json.loads((ROOT / "ios/native-dependencies.lock.json").read_text())["moltenVkValidation"]
    package = ROOT / f'ios/build/MoltenVK-validation-{validation["version"]}.tar'
    if not package.exists():
        request = urllib.request.Request(validation["url"], headers={"User-Agent": "ryu-ios-build/1"})
        with urllib.request.urlopen(request, timeout=120) as response, package.open("wb") as target:
            while block := response.read(1024 * 1024):
                target.write(block)
    if hashlib.sha256(package.read_bytes()).hexdigest() != validation["sha256"]:
        raise RuntimeError("MoltenVK validation package checksum mismatch")
    with tarfile.open(package) as tar:
        prefix = "MoltenVK/MoltenVK/dynamic/MoltenVK.xcframework/"
        members = [m for m in tar if m.name.startswith(prefix) and
                   ("/macos-" in m.name or "/ios-arm64_x86_64-simulator/" in m.name)]
        tar.extractall(output, members=members, filter="data")
    print("Official macOS/simulator MoltenVK validation frameworks verified.")
