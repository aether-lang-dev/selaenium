#!/usr/bin/env python3
"""Vendor selected Selaenium source sets and release libraries into a repo."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tarfile
import tempfile


REPOSITORY = "aether-lang-dev/selaenium"
SCHEMA = 1
TAG_RE = re.compile(r"v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?\Z")
PLATFORMS = {
    "linux-x86_64": ("linux", "x86_64", "so", "libselenium_core.so"),
    "linux-arm64": ("linux", "arm64", "so", "libselenium_core.so"),
    "linux-x86_64-musl": ("linux", "x86_64-musl", "so", "libselenium_core.so"),
    "linux-arm64-musl": ("linux", "arm64-musl", "so", "libselenium_core.so"),
    "macos-x86_64": ("macos", "x86_64", "dylib", "libselenium_core.dylib"),
    "macos-arm64": ("macos", "arm64", "dylib", "libselenium_core.dylib"),
    "windows-x86_64": ("windows", "x86_64", "dll", "selenium_core.dll"),
    "windows-arm64": ("windows", "arm64", "dll", "selenium_core.dll"),
    "freebsd-x86_64": ("freebsd", "x86_64", "so", "libselenium_core.so"),
}


class VendorError(Exception):
    pass


def run_gh(args: list[str], *, output: Path | None = None) -> bytes:
    command = ["gh", *args]
    try:
        result = subprocess.run(command, check=True, capture_output=True)
    except FileNotFoundError as error:
        raise VendorError("gh is required; install GitHub CLI and authenticate it") from error
    except subprocess.CalledProcessError as error:
        detail = error.stderr.decode(errors="replace").strip()
        raise VendorError(f"{' '.join(command)} failed: {detail}") from error
    data = result.stdout
    if output is not None:
        output.write_bytes(data)
    return data


def resolve_commit(tag: str) -> str:
    raw = run_gh(["api", f"repos/{REPOSITORY}/commits/{tag}"])
    try:
        sha = json.loads(raw)["sha"]
    except (json.JSONDecodeError, KeyError, TypeError) as error:
        raise VendorError(f"could not resolve {tag} to a commit SHA") from error
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise VendorError(f"GitHub returned an invalid commit SHA for {tag}: {sha!r}")
    return sha


def archive_files(archive: Path, source_sets: list[dict[str, str]]) -> dict[str, bytes]:
    """Read only requested regular files from GitHub's commit tarball."""
    wanted: dict[str, bytes] = {}
    prefixes = [item["source"].rstrip("/") for item in source_sets]
    matched = {prefix: False for prefix in prefixes}
    with tarfile.open(archive, "r:gz") as tar:
        for member in tar:
            path = PurePosixPath(member.name)
            if not member.isfile() or ".." in path.parts:
                continue
            # GitHub archives have one generated top-level directory.
            relative = PurePosixPath(*path.parts[1:])
            for prefix in prefixes:
                if str(relative) == prefix or str(relative).startswith(prefix + "/"):
                    matched[prefix] = True
                    if str(relative) in wanted:
                        raise VendorError(f"source sets overlap at {relative}")
                    stream = tar.extractfile(member)
                    if stream is None:
                        raise VendorError(f"could not read {relative} from source archive")
                    wanted[str(relative)] = stream.read()
    for prefix, found in matched.items():
        if not found:
            raise VendorError(f"source path not found in the tag: {prefix}")
    return wanted


def asset_name(tag: str, platform: str) -> str:
    os_name, arch, extension, _ = PLATFORMS[platform]
    return f"libselenium_core-{tag}-{os_name}-{arch}.{extension}"


def download_release_assets(tag: str, platforms: list[str], directory: Path) -> dict[str, dict[str, object]]:
    names = [asset_name(tag, platform) for platform in platforms]
    patterns = [pattern for name in names for pattern in (name, name + ".sha256")]
    command = ["release", "download", tag, "--repo", REPOSITORY, "--dir", str(directory)]
    for pattern in patterns:
        command.extend(["--pattern", pattern])
    run_gh(command)

    result: dict[str, dict[str, object]] = {}
    for platform, name in zip(platforms, names, strict=True):
        binary = directory / name
        sidecar = directory / (name + ".sha256")
        if not binary.is_file() or binary.stat().st_size == 0:
            raise VendorError(f"release asset is missing or empty: {name}")
        digest = sha256_file(binary)
        parts = sidecar.read_text(encoding="utf-8").split()
        if parts != [digest, name]:
            raise VendorError(f"release checksum sidecar does not match {name}")
        result[platform] = {"asset": name, "sha256": digest, "bytes": binary.read_bytes()}
    return result


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_relative(value: str, label: str) -> str:
    path = PurePosixPath(value)
    if path.is_absolute() or not path.parts or ".." in path.parts or "." in path.parts:
        raise VendorError(f"{label} must be a repo-relative path without '..': {value}")
    return str(path)


def output_path(root: Path, relative: str, label: str) -> Path:
    """Resolve a manifest-relative output while refusing symlink escapes."""
    relative = safe_relative(relative, label)
    resolved_root = root.resolve()
    destination = root / relative
    if not destination.resolve().is_relative_to(resolved_root):
        raise VendorError(f"{label} escapes the manifest directory through a symlink: {destination}")
    return destination


def parse_source_set(value: str) -> dict[str, str]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("use REPO_PATH=DESTINATION, e.g. java/src/main/java=vendor/selaenium/java")
    source, destination = value.split("=", 1)
    try:
        source = safe_relative(source, "source path")
        destination = safe_relative(destination, "destination")
    except VendorError as error:
        raise argparse.ArgumentTypeError(str(error)) from error
    return {"source": source, "destination": destination}


def destination_map(
    source_sets: list[dict[str, str]],
    source_files: dict[str, bytes],
    native_dir: str | None,
    platforms: list[str],
    assets: dict[str, dict[str, object]],
) -> dict[str, dict[str, object]]:
    files: dict[str, dict[str, object]] = {}
    for item in source_sets:
        prefix = item["source"].rstrip("/")
        dest = item["destination"].rstrip("/")
        matches = [path for path in source_files if path == prefix or path.startswith(prefix + "/")]
        if not matches:
            raise VendorError(f"source set contains no files: {prefix}")
        for source_path in matches:
            suffix = source_path[len(prefix):].lstrip("/")
            output = f"{dest}/{suffix}" if suffix else f"{dest}/{PurePosixPath(prefix).name}"
            files[output] = {
                "kind": "source",
                "source_path": source_path,
                "sha256": hashlib.sha256(source_files[source_path]).hexdigest(),
                "bytes": source_files[source_path],
            }
    if native_dir:
        for platform in platforms:
            _, _, _, filename = PLATFORMS[platform]
            output = f"{native_dir}/{platform}/{filename}"
            files[output] = {
                "kind": "native",
                "platform": platform,
                "asset": assets[platform]["asset"],
                "sha256": assets[platform]["sha256"],
                "bytes": assets[platform]["bytes"],
            }
    return files


def load_manifest(path: Path) -> dict[str, object] | None:
    if not path.exists():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise VendorError(f"cannot read existing manifest {path}: {error}") from error
    if not isinstance(data, dict) or data.get("schema") != SCHEMA or data.get("repository") != REPOSITORY:
        raise VendorError(f"unsupported or foreign vendor manifest: {path}")
    return data


def write_sync(args: argparse.Namespace) -> None:
    if not args.source_set and not args.native_libs:
        raise VendorError("specify at least one --source-set or --native-libs destination")
    if args.platform and not args.native_libs:
        raise VendorError("--platform requires --native-libs")
    if args.native_libs and not args.platform:
        raise VendorError("--native-libs requires at least one --platform")
    if len(set(args.platform)) != len(args.platform):
        raise VendorError("each --platform may be specified only once")
    manifest_path = args.manifest.resolve()
    manifest_root = manifest_path.parent
    native_dir = safe_relative(args.native_libs, "--native-libs") if args.native_libs else None
    source_sets = args.source_set
    destinations = [item["destination"] for item in source_sets]
    if native_dir:
        destinations.append(native_dir)
    if len(set(destinations)) != len(destinations):
        raise VendorError("source-set and native destinations must be distinct")
    for index, left in enumerate(destinations):
        for right in destinations[index + 1:]:
            if left.startswith(right + "/") or right.startswith(left + "/"):
                raise VendorError("source-set and native destinations must not overlap")

    tag = args.tag
    if not TAG_RE.fullmatch(tag):
        raise VendorError("tag must look like v1.2.3 or v1.2.3-alpha.1")
    commit = resolve_commit(tag)

    with tempfile.TemporaryDirectory(prefix="selaenium-vendor-") as temp:
        temp_path = Path(temp)
        source_files = {}
        if source_sets:
            archive = temp_path / "source.tar.gz"
            run_gh(["api", f"repos/{REPOSITORY}/tarball/{commit}"], output=archive)
            source_files = archive_files(archive, source_sets)
        assets = download_release_assets(tag, args.platform, temp_path) if args.platform else {}
        files = destination_map(source_sets, source_files, native_dir, args.platform, assets)

    previous = load_manifest(manifest_path)
    old_files = {item["path"] for item in (previous or {}).get("files", [])}
    output_roots = destinations

    def is_managed_output(relative: str) -> bool:
        return any(relative == root or relative.startswith(root.rstrip("/") + "/") for root in output_roots)

    # Refuse to overwrite files the manifest does not already own.
    for relative in files:
        destination = output_path(manifest_root, relative, "destination")
        if destination.exists() and (relative not in old_files or not is_managed_output(relative)):
            raise VendorError(f"refusing to overwrite untracked file: {destination}")

    for relative, item in files.items():
        destination = output_path(manifest_root, relative, "destination")
        destination.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=destination.parent, prefix=destination.name + ".", delete=False) as temp_file:
            temp_file.write(item["bytes"])
            temp_name = Path(temp_file.name)
        os.replace(temp_name, destination)

    current_paths = set(files)
    for relative in old_files - current_paths:
        if not is_managed_output(relative):
            continue
        stale = output_path(manifest_root, relative, "old manifest path")
        if stale.is_file():
            stale.unlink()
    records = [{key: value for key, value in item.items() if key != "bytes"} | {"path": path}
               for path, item in sorted(files.items())]
    document = {
        "schema": SCHEMA,
        "repository": REPOSITORY,
        "tag": tag,
        "commit": commit,
        "source_sets": source_sets,
        "native_libs": {"destination": native_dir, "platforms": args.platform} if native_dir else None,
        "files": records,
    }
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=manifest_path.parent,
                                     prefix=manifest_path.name + ".", delete=False) as temp_manifest:
        temp_manifest.write(json.dumps(document, indent=2, sort_keys=True) + "\n")
        temp_manifest_name = Path(temp_manifest.name)
    os.replace(temp_manifest_name, manifest_path)
    print(f"Vendored {len(source_files)} source files and {len(args.platform)} native libraries from {tag} ({commit[:12]}).")
    print(f"Manifest: {manifest_path}")


def verify_manifest(manifest_path: Path) -> None:
    manifest_path = manifest_path.resolve()
    data = load_manifest(manifest_path)
    if data is None:
        raise VendorError(f"manifest not found: {manifest_path}")
    tag = data.get("tag")
    if not isinstance(tag, str) or not TAG_RE.fullmatch(tag):
        raise VendorError("manifest has an invalid tag")
    commit = resolve_commit(tag)
    if commit != data.get("commit"):
        raise VendorError(f"tag {tag} now resolves to {commit}, manifest records {data.get('commit')}")
    source_sets = data.get("source_sets") or []
    native = data.get("native_libs")
    native_dir = native["destination"] if native else None
    platforms = native["platforms"] if native else []

    with tempfile.TemporaryDirectory(prefix="selaenium-verify-") as temp:
        temp_path = Path(temp)
        source_files = {}
        if source_sets:
            archive = temp_path / "source.tar.gz"
            run_gh(["api", f"repos/{REPOSITORY}/tarball/{commit}"], output=archive)
            source_files = archive_files(archive, source_sets)
        assets = download_release_assets(tag, platforms, temp_path) if platforms else {}
        expected = destination_map(source_sets, source_files, native_dir, platforms, assets)

    recorded = {item["path"]: item for item in data.get("files", [])}
    if set(expected) != set(recorded):
        raise VendorError("manifest file list differs from the selected source sets or release assets")
    for relative, item in expected.items():
        record = recorded[relative]
        digest = hashlib.sha256(item["bytes"]).hexdigest()
        if digest != record.get("sha256"):
            raise VendorError(f"manifest hash differs from tag for {relative}")
        vendored = output_path(manifest_path.parent, relative, "manifest path")
        if not vendored.is_file() or sha256_file(vendored) != digest:
            raise VendorError(f"vendored file differs from {tag}: {vendored}")
    print(f"Verified {len(expected)} vendored files against {tag} ({commit[:12]}), including release checksums.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    sync = subparsers.add_parser("sync", help="copy selected files from a Selaenium tag")
    sync.add_argument("--tag", required=True, help="release tag, e.g. v0.11.0")
    sync.add_argument("--source-set", action="append", type=parse_source_set, default=[], metavar="REPO_PATH=DESTINATION",
                      help="copy a repo path (file or directory) to a destination; repeatable")
    sync.add_argument("--native-libs", metavar="DESTINATION", help="destination for selected native libraries")
    sync.add_argument("--platform", action="append", choices=sorted(PLATFORMS), default=[],
                      help="native platform to vendor; repeatable")
    sync.add_argument("--manifest", type=Path, default=Path("selaenium-vendor.json"),
                      help="provenance manifest path (default: ./selaenium-vendor.json)")
    sync.set_defaults(func=write_sync)

    verify = subparsers.add_parser("verify", help="verify a vendored snapshot against its recorded tag")
    verify.add_argument("manifest", type=Path)
    verify.set_defaults(func=lambda args: verify_manifest(args.manifest))

    args = parser.parse_args()
    try:
        args.func(args)
    except (VendorError, OSError, tarfile.TarError) as error:
        print(f"vendor: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
