"""Compile pinned, portable FSR1 shaders for Vulkan. No platform DLLs are used."""
import hashlib
import io
from pathlib import Path
import platform
import subprocess
import zipfile
import urllib.request

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
REVISION = "7539ae8b6568ad29ed78a753404351daf3b5cca7"
COMPILERS = {
    "Windows": ("windows-x86_64", "82bf434e69b9bb4829de7e2b4bc2c5e7a7861e53d66cf75e5cc70f5f694a8d9b"),
    "Darwin": ("macos-universal", "1086bc6c7ce8ff188e4e1d1a69078e9e38156a4c2c3f13e4f91b9289a1d90453"),
}

def main():
    assert hashlib.sha256((HERE / "upstream/ffx_fsr1.h").read_bytes()).hexdigest() == "e6f6c9d0d922e50bdf4e6b171da5b8dc4a6fa4da9121d9b3059769125e8f0375", "Vendored AMD shader source changed"
    name, digest = COMPILERS[platform.system()]
    cache = ROOT / "ios/build/fsr-tools"
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / f"glslang-16.6.0-{name}.zip"
    if not archive.exists():
        url = f"https://github.com/KhronosGroup/glslang/releases/download/16.6.0/glslang-16.6.0-{name}-release.zip"
        with urllib.request.urlopen(url, timeout=120) as response:
            archive.write_bytes(response.read())
    data = archive.read_bytes()
    if hashlib.sha256(data).hexdigest() != digest:
        raise RuntimeError("Shader compiler archive failed its SHA-256 check")
    executable = "glslang.exe" if platform.system() == "Windows" else "glslang"
    compiler = cache / executable
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        matches = [p for p in z.namelist() if Path(p).name in (executable, "glslangValidator.exe" if platform.system() == "Windows" else "glslangValidator")]
        assert len(matches) == 1, matches
        compiler.write_bytes(z.read(matches[0]))
    if platform.system() != "Windows":
        compiler.chmod(0o755)
    destination = ROOT / "ios/build/melonx/src/Ryujinx.Graphics.Vulkan/Effects/Shaders"
    for stem in ("FsrScaling", "FsrSharpening"):
        target = destination / (stem + ".spv")
        subprocess.run([str(compiler), "-V", "--target-env", "vulkan1.1", "-Os", "-S", "comp",
                        "-I" + str(HERE), str(HERE / (stem + ".comp")), "-o", str(target)], check=True)
        source = (HERE / (stem + ".comp")).read_text(encoding="utf-8")
        (destination / (stem + ".glsl")).write_text(source, encoding="utf-8", newline="\n")
        print(f"PASS {stem}: current AMD FSR1 GPU source {REVISION[:7]}; portable SPIR-V compiled")

if __name__ == "__main__":
    main()
