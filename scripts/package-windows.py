#!/usr/bin/env python3
"""Build local, unsigned Windows distribution ZIPs without publishing anything."""
import argparse
import hashlib
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile


ROOT = Path(__file__).resolve().parent.parent
ARCHITECTURES = {"arm64": 0xAA64, "x64": 0x8664}


def machine(executable):
    with executable.open("rb") as source:
        if source.read(2) != b"MZ":
            raise ValueError(f"Not a Windows executable: {executable}")
        source.seek(0x3C)
        source.seek(int.from_bytes(source.read(4), "little"))
        if source.read(4) != b"PE\0\0":
            raise ValueError(f"Missing PE signature: {executable}")
        return int.from_bytes(source.read(2), "little")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--dotnet", default="dotnet")
    args = parser.parse_args()
    if not re.fullmatch(r"\d+\.\d+\.\d+", args.version):
        parser.error("version must be MAJOR.MINOR.PATCH")
    if subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip():
        parser.error("package from a clean checkout so commit.txt identifies the sources")
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    args.output.mkdir(parents=True, exist_ok=True)
    sums = []
    with tempfile.TemporaryDirectory(prefix="gitgaze-", dir=args.output) as temporary:
        staging = Path(temporary).resolve()
        for arch, expected in ARCHITECTURES.items():
            payload = staging / arch
            subprocess.run([args.dotnet, "publish", str(ROOT / "Windows/GitGaze.Windows.csproj"), "-c", "Release",
                            "-r", f"win-{arch}", "--self-contained", f"-p:Version={args.version}", "-o", str(payload)], check=True)
            if machine(payload / "GitGaze.exe") != expected:
                raise ValueError(f"Published executable is not {arch}")
            (payload / "LICENSE").write_bytes((ROOT / "LICENSE").read_bytes())
            (payload / "commit.txt").write_text(revision + "\n", encoding="ascii")
            name = f"GitGaze-{args.version}-win-{arch}-unsigned.zip"
            archive = staging / name
            with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as output:
                for entry in sorted(payload.rglob("*")):
                    if entry.is_file():
                        output.write(entry, entry.relative_to(payload))
            with zipfile.ZipFile(archive) as output:
                if output.testzip() or "SharedClient/dashboard.html" not in output.namelist():
                    raise ValueError(f"Archive failed verification: {archive}")
            with archive.open("rb") as source:
                sums.append(f"{hashlib.file_digest(source, 'sha256').hexdigest()}  {name}")
        for archive in staging.glob("*.zip"):
            archive.replace(args.output / archive.name)
    (args.output / "SHA256SUMS").write_text("\n".join(sums) + "\n", encoding="ascii")
    print(f"Unsigned Windows packages ready in {args.output} (not published)")


if __name__ == "__main__":
    main()
