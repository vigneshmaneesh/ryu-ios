"""Run the actual iOS core on small and explicit-size pthread stacks."""
from pathlib import Path
import subprocess
import sys

device, output = sys.argv[1], Path(sys.argv[2])
for name, stack in (("small-stack", 512 * 1024), ("core-worker", 8 * 1024 * 1024)):
    directory = output / name
    directory.mkdir(exist_ok=True)
    result = subprocess.run(
        ["xcrun", "simctl", "spawn", device, str(output / "IosStartupChecks"), str(directory), str(stack)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
    (directory / "process.log").write_text(result.stdout)
    print(f"{name}: exit {result.returncode}\n{result.stdout}", flush=True)
    trace = directory / "horizon-last-run.log"
    print(trace.read_text() if trace.exists() else "No startup journal was created.", flush=True)
    if name == "core-worker":
        if result.returncode != 0:
            raise SystemExit("The app's explicit-stack core worker failed iOS startup.")
        if not trace.exists() or "RESULT PASS" not in trace.read_text():
            raise SystemExit("Missing successful kernel teardown checkpoint.")
