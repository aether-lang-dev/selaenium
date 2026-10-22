#!/usr/bin/env python3
"""Check the complete release asset set, checksums, and the loadable Linux ABI."""

import argparse
import ctypes
import hashlib
from pathlib import Path
import re
import subprocess
import tarfile


ROOT = Path(__file__).resolve().parent.parent
PLATFORMS = (
    ("linux", "x86_64", "so"), ("linux", "arm64", "so"),
    ("linux", "x86_64-musl", "so"), ("linux", "arm64-musl", "so"),
    ("macos", "x86_64", "dylib"), ("macos", "arm64", "dylib"),
    ("windows", "x86_64", "dll"), ("windows", "arm64", "dll"),
    ("freebsd", "x86_64", "so"),
)


def check_artifacts(tag, dist, engine_only=False):
    manifest = {}
    manifest_path = dist / "SHA256SUMS.txt"
    if manifest_path.exists():
        for line in manifest_path.read_text().splitlines():
            digest, name = line.split()
            manifest[name.removeprefix("./")] = digest
    elif not engine_only:
        raise ValueError("missing SHA256SUMS.txt")
    for os_name, arch, extension in PLATFORMS:
        name = f"libselenium_core-{tag}-{os_name}-{arch}.{extension}"
        names = (name, name + ".lib") if os_name == "windows" else (name,)
        for filename in names:
            artifact = dist / filename
            digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
            if artifact.stat().st_size == 0:
                raise ValueError(f"empty artifact: {filename}")
            sidecar = (dist / (filename + ".sha256")).read_text().split()
            if sidecar != [digest, filename] or (manifest and manifest.get(filename) != digest):
                raise ValueError(f"checksum mismatch: {filename}")
        if os_name == "linux":
            dynamic = subprocess.run(["readelf", "-d", str(dist / name)], check=True, capture_output=True, text=True).stdout
            needed = re.findall(r"\(NEEDED\).*?\[([^\]]+)\]", dynamic)
            expected = "libc.so" if arch.endswith("-musl") else "libc.so.6"
            other = "libc.so.6" if arch.endswith("-musl") else "libc.so"
            if expected not in needed or other in needed:
                raise ValueError(f"wrong Linux libc for {name}: {needed}")
    if not engine_only:
        for filename, digest in manifest.items():
            artifact = dist / filename
            actual = hashlib.sha256(artifact.read_bytes()).hexdigest()
            if actual != digest or artifact.stat().st_size == 0:
                raise ValueError(f"checksum mismatch or empty release asset: {filename}")
            sidecar = (dist / (filename + ".sha256")).read_text().split()
            if sidecar != [digest, filename]:
                raise ValueError(f"checksum sidecar mismatch: {filename}")
        source_archives = {
            f"selenium-crystal-{tag}.tar.gz": (
                "selenium-crystal",
                ("shard.yml", "src/selenium.cr", "bin/crystal-build",
                 "scripts/fetch-engine.sh", "SELENIUM_CORE_VERSION"),
            ),
            f"selenium-julia-{tag}.tar.gz": (
                "Selenium",
                ("Project.toml", "src/Selenium.jl", "README.md"),
            ),
        }
        for filename, (topdir, required) in source_archives.items():
            archive = dist / filename
            with tarfile.open(archive, "r:gz") as tar:
                members = {member.name for member in tar.getmembers()}
            for path in required:
                if f"{topdir}/{path}" not in members:
                    raise ValueError(f"{filename} is missing {topdir}/{path}")
            native = (".so", ".dylib", ".dll")
            if any(name.endswith(native) for name in members):
                raise ValueError(f"source archive contains a platform native library: {filename}")
    lib = ctypes.CDLL(str((dist / f"libselenium_core-{tag}-linux-x86_64.so").resolve()))
    exports = re.findall(r"^(sel_embed_\w+)\(", (ROOT / "selenium_core/embed.ae").read_text(), re.MULTILINE)
    if not exports:
        raise ValueError("no engine ABI declarations found")
    for symbol in exports:
        getattr(lib, "aether_" + symbol)
    print(f"Verified all nine engine libraries, Windows import libraries, checksums, and {len(exports)} Linux ABI exports.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag")
    parser.add_argument("--dist", type=Path, default=ROOT / "release/dist")
    parser.add_argument("--engine-only", action="store_true",
                        help="verify native libraries before package assets and manifest are staged")
    args = parser.parse_args()
    if not re.fullmatch(r"v\d+\.\d+\.\d+", args.tag):
        parser.error("expected a release tag vX.Y.Z")
    try:
        check_artifacts(args.tag, args.dist, args.engine_only)
    except (OSError, ValueError, AttributeError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"artifacts: {error}\n")


if __name__ == "__main__":
    main()
