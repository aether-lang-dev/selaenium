#!/bin/sh
# fetch-engine.sh — download + cache the prebuilt pure-Aether engine
# (libselenium_core) from the project's GitHub releases, so a dev building a
# LINK-TIME binding (rust/go/c/cpp/nim/zig/…) needs no Aether toolchain.
#
#   scripts/fetch-engine.sh                 # this platform, the pinned tag
#   TAG=v0.8.0 scripts/fetch-engine.sh      # pin an engine release
#   FORCE=1   scripts/fetch-engine.sh       # re-download
#   scripts/fetch-engine.sh --path          # just print the cache path, don't fetch
#
# It writes to the SAME per-user cache the runtime bindings (ruby/python/dart/
# php/lua/julia) use — $XDG_CACHE_HOME/selaenium/<tag>/libselenium_core.<ext>
# (~/.cache on Linux, ~/Library/Caches on macOS, %LOCALAPPDATA% on Windows) — so
# every binding shares one downloaded engine. The link-time build scripts add
# that dir to their library search path, so after running this once you just
# build normally.
#
# Portable POSIX sh; needs curl or wget, and sha256sum or shasum. Verifies the
# published .sha256 sidecar. Idempotent: a present, checksum-matching copy is a
# no-op.
set -eu

TAG="${TAG:-v0.8.0}"          # the engine gh-release tag (matches the bindings' ENGINE_VERSION)
REPO="aether-lang-dev/selaenium"
BASE="https://github.com/${REPO}/releases/download"

path_only=0
[ "${1:-}" = "--path" ] && path_only=1

# ---- platform -> release asset name (matches release/build.sh) ----
uname_s="$(uname -s 2>/dev/null || echo unknown)"
uname_m="$(uname -m 2>/dev/null || echo unknown)"

case "$uname_s" in
  Linux)   os=linux;   ext=so    ;;
  Darwin)  os=macos;   ext=dylib ;;
  FreeBSD) os=freebsd; ext=so    ;;
  MINGW*|MSYS*|CYGWIN*|Windows*) os=windows; ext=dll ;;
  *) echo "fetch-engine: unsupported OS: $uname_s" >&2; exit 1 ;;
esac
case "$uname_m" in
  x86_64|amd64)   arch=x86_64 ;;
  arm64|aarch64)  arch=arm64  ;;
  *) echo "fetch-engine: unsupported CPU: $uname_m" >&2; exit 1 ;;
esac

asset="libselenium_core-${TAG}-${os}-${arch}.${ext}"

# ---- cache dir (identical convention to the runtime bindings) ----
if [ -n "${XDG_CACHE_HOME:-}" ]; then
  base_cache="$XDG_CACHE_HOME"
elif [ "$os" = macos ]; then
  base_cache="$HOME/Library/Caches"
elif [ "$os" = windows ]; then
  base_cache="${LOCALAPPDATA:-$HOME/AppData/Local}"
else
  base_cache="$HOME/.cache"
fi
cache_dir="$base_cache/selaenium/$TAG"
# The bare filename the binding loaders/linkers look for.
case "$os" in
  windows) libname="selenium_core.dll" ;;
  macos)   libname="libselenium_core.dylib" ;;
  *)       libname="libselenium_core.so" ;;
esac
dest="$cache_dir/$libname"

if [ "$path_only" = 1 ]; then
  echo "$dest"
  exit 0
fi

# ---- helpers ----
have() { command -v "$1" >/dev/null 2>&1; }

fetch_to() { # url dest
  if have curl; then curl -fsSL -o "$2" "$1"
  elif have wget; then wget -q -O "$2" "$1"
  else echo "fetch-engine: need curl or wget" >&2; exit 1
  fi
}

sha256_of() { # path -> hex on stdout (empty if no tool)
  if have sha256sum; then sha256sum "$1" | awk '{print $1}'
  elif have shasum; then shasum -a 256 "$1" | awk '{print $1}'
  else echo ""
  fi
}

# published sidecar hex ("" if unavailable)
want=""
sidecar_tmp="$(mktemp)"
if fetch_to "${BASE}/${TAG}/${asset}.sha256" "$sidecar_tmp" 2>/dev/null; then
  want="$(awk '{print $1; exit}' "$sidecar_tmp")"
fi
rm -f "$sidecar_tmp"

# idempotent: present + checksum-matching copy is a no-op
if [ "${FORCE:-0}" != 1 ] && [ -f "$dest" ]; then
  if [ -z "$want" ] || [ "$(sha256_of "$dest")" = "$want" ]; then
    echo "fetch-engine: already cached: $dest" >&2
    echo "$dest"
    exit 0
  fi
fi

mkdir -p "$cache_dir"
echo "fetch-engine: downloading $asset ($TAG) ..." >&2
tmp="$dest.$$.part"
fetch_to "${BASE}/${TAG}/${asset}" "$tmp"

if [ -n "$want" ]; then
  got="$(sha256_of "$tmp")"
  if [ -n "$got" ] && [ "$got" != "$want" ]; then
    rm -f "$tmp"
    echo "fetch-engine: checksum mismatch for $asset: expected $want, got $got" >&2
    exit 1
  fi
fi

mv -f "$tmp" "$dest"     # atomic within the cache dir
echo "fetch-engine: engine ready at $dest" >&2
echo "fetch-engine: now build normally — the link-time build scripts search this cache." >&2
echo "$dest"
