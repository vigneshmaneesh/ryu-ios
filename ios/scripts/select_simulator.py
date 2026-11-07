"""Choose a compatible iOS simulator from the runner's actual inventory."""
import json
import sys

inventory = json.load(open(sys.argv[1], encoding="utf-8"))
types = inventory["devicetypes"]
runtimes = sorted((r for r in inventory["runtimes"] if r.get("isAvailable")
    and ".iOS-" in r["identifier"] and int(r["version"].split(".")[0]) >= 18),
    key=lambda r: tuple(map(int, r["version"].split("."))), reverse=True)
for runtime in runtimes:
    existing = inventory.get("devices", {}).get(runtime["identifier"], [])
    for device in existing:
        if not device.get("isAvailable") or not device["name"].startswith("iPhone"):
            continue
        matching = next((t for t in types if t["identifier"] == device.get("deviceTypeIdentifier")
                         or t["name"] == device["name"]), None)
        if matching:
            print(runtime["identifier"] + "\t" + matching["identifier"])
            sys.exit(0)
    version = list(map(int, runtime["version"].split("."))) + [0, 0]
    encoded = (version[0] << 16) | (version[1] << 8) | version[2]
    matching = [t for t in types if t.get("productFamily") == "iPhone"
        and t.get("minRuntimeVersion", 0) <= encoded <= t.get("maxRuntimeVersion", 0xffffffff)]
    if matching:
        device = max(matching, key=lambda t: t.get("minRuntimeVersion", 0))
        print(runtime["identifier"] + "\t" + device["identifier"])
        sys.exit(0)
raise RuntimeError("No compatible, available iOS simulator runtime/device combination")
