"""Launch the signed UIKit regression app, retain its trace and composed frame."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time

device, app, out = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
bundle = "app.ryu.ios.GraphicsChecks"
subprocess.run(["xcrun", "simctl", "install", device, str(app)], check=True, timeout=180)
container = Path(subprocess.check_output(
    ["xcrun", "simctl", "get_app_container", device, bundle, "data"], text=True, timeout=60).strip())
documents = container / "Documents"
result_file = documents / "graphics-result.json"
with (out / "renderer-process.log").open("w") as log:
    process = subprocess.Popen(["xcrun", "simctl", "launch", "--terminate-running-process", "--console-pty", device, bundle],
        stdout=log, stderr=subprocess.STDOUT)
    try:
        deadline = time.monotonic() + 120
        while not result_file.exists() and time.monotonic() < deadline:
            if process.poll() is not None:
                break
            time.sleep(0.25)
        for name in ("graphics-result.json", "graphics-last-run.log"):
            if (documents / name).exists():
                shutil.copyfile(documents / name, out / name)
        if not result_file.exists():
            raise RuntimeError("The iOS graphics app exited or timed out before saving its result.")
        result = json.loads(result_file.read_text())
        print(json.dumps(result, indent=2), flush=True)
        if result["status"] != 0 or result["runs"] != 2:
            raise RuntimeError("Production iOS renderer checks failed.")
        subprocess.run(["xcrun", "simctl", "io", device, "screenshot", str(out / "renderer-screen.png")],
            check=True, timeout=60)
    finally:
        subprocess.run(["xcrun", "simctl", "terminate", device, bundle], check=False, timeout=30)
        try:
            process.wait(timeout=30)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=10)
        print((out / "renderer-process.log").read_text()[-16000:], flush=True)
        trace = out / "graphics-last-run.log"
        if trace.exists():
            print(trace.read_text(), flush=True)
