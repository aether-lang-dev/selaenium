#!/usr/bin/env bash
# Cross-build the engine (libselenium_core) for the release matrix from ONE host,
# and emit each artifact with a .sha256 — ready for out-of-band on-target
# attestation (a homelab runs the suite on real hardware and attests a hash).
#
# The engine is pure Aether; `ae build --target=<triple>` cross-compiles via zig
# cc, no per-OS runner. Output name: libselenium_core-<tag>-<os>-<arch>.<ext>
# (.so linux / .dylib macos / .dll windows). Alongside each: <artifact>.sha256,
# and a combined release/dist/SHA256SUMS.txt.
#
# Usage:
#   release/build.sh                    # core matrix (linux+macos amd64/arm64)
#   RELEASE_EXTRA_TARGETS=1 release/build.sh   # + windows (slow) + freebsd (needs sysroot)
#   RELEASE_TAG=v1.2.3 release/build.sh  # stamp the tag into artifact names
#                                          (default: `git describe`, else "dev")
#   TARGETS="aarch64-macos" release/build.sh   # override the matrix entirely
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck disable=SC1091
. "$HERE/targets.env"
cd "$ROOT"

export PATH="${PREFIX:-$HOME/.local}/bin:$HOME/.aether/bin:$PATH"

say()  { printf 'release: %s\n' "$*"; }
die()  { printf 'release: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

have ae || die "ae not on PATH (run ci/toolchain.sh first)"
have zig || die "zig not on PATH — required for cross-compilation (ae build --target)"
have sha256sum || die "sha256sum required to checksum artifacts"

TAG="${RELEASE_TAG:-$(git describe --tags --always 2>/dev/null || echo dev)}"

# Resolve the matrix.
if [ -n "${TARGETS:-}" ]; then
  MATRIX="$TARGETS"
else
  MATRIX="$RELEASE_TARGETS"
  [ "${RELEASE_EXTRA_TARGETS:-0}" = "1" ] && MATRIX="$MATRIX $RELEASE_EXTRA_TARGETS_LIST"
fi

DIST="$ROOT/release/dist"
rm -rf "$DIST"; mkdir -p "$DIST"

# triple -> {os, arch, extension} for the artifact name.
os_of()  { case "$1" in *-linux|*-linux-musl) echo linux;; *-macos) echo macos;; *-windows) echo windows;; *-freebsd) echo freebsd;; *) echo unknown;; esac; }
arch_of(){ case "$1" in aarch64-*) echo arm64;; x86_64-*) echo amd64;; *) echo "$1";; esac; }
ext_of() { case "$1" in *-macos) echo dylib;; *-windows) echo dll;; *) echo so;; esac; }

say "engine: libselenium_core  tag: $TAG"
say "matrix: $MATRIX"
echo

built=0; failed=0
for t in $MATRIX; do
  os=$(os_of "$t"); arch=$(arch_of "$t"); ext=$(ext_of "$t")
  name="libselenium_core-${TAG}-${os}-${arch}.${ext}"
  out="$DIST/$name"
  log="$DIST/.$t.log"

  # FreeBSD needs a base sysroot; skip loudly rather than fail if it's absent.
  if [ "$os" = "freebsd" ] && [ -z "${AETHER_SYSROOT:-}" ]; then
    say "SKIP $t — set AETHER_SYSROOT to a FreeBSD base sysroot (see aether-crossbuild)"
    continue
  fi

  printf 'release:   %-18s -> %s ... ' "$t" "$name"
  # --with=net,os,fs: the engine's caps (driver orchestration spawns processes
  #   [os] and reads the driver cache [fs], not just net). --lib drivermgr: the
  #   Selenium-Manager module tree embed.ae imports by bare name (resolve/
  #   browser/cft/cache/...) — without it aetherc can't resolve resolve_chrome.
  #   These mirror selenium_core/.build.ae's caps("net,os,fs") + lib("drivermgr").
  # --extra takes an ABSOLUTE path: ae >=0.638's cross path (--target) no longer
  # resolves a relative --extra C file from CWD (the native path was forgiving,
  # which is why this worked pre-0.638). An absolute path builds on every target.
  if ( cd "$ROOT/selenium_core" \
       && ae build --emit=lib --with=net,os,fs --lib drivermgr --size --target="$t" \
            embed.ae --extra "$ROOT/selenium_core/_embed_strdup.c" -o "$out" ) >"$log" 2>&1; then
    ( cd "$DIST" && sha256sum "$name" > "$name.sha256" )
    # Windows emits an import library (<dll>.lib) beside the DLL — needed by a
    # consumer that LINKS against the DLL at build time (our FFI bindings dlopen
    # at runtime and don't need it, but ship it so Windows is first-class).
    # Checksum it too.
    if [ "$os" = "windows" ] && [ -f "$out.lib" ]; then
      ( cd "$DIST" && sha256sum "$name.lib" > "$name.lib.sha256" )
    fi
    printf 'ok  (%s)\n' "$(file -b "$out" 2>/dev/null | cut -c1-42)"
    built=$((built+1))
    rm -f "$log"
  else
    printf 'FAILED\n'
    sed 's/^/release:     /' "$log" | grep -iE 'error|fatal' | head -3
    failed=$((failed+1))
  fi
done

# ---- the multi-platform Java jars ----
# The 3 jars (lean / per-platform / standalone) are a distinct deliverable from the
# raw engine libs: aeb cross-builds the native matrix (with size()) and cross-packages
# them here. Build via aeb, then stage each jar into DIST with its own .sha256 so it
# rides the same release + manifest. Skipped (with a note) if no JDK/aeb — the engine
# libs still ship. Set RELEASE_NO_JARS=1 to skip explicitly.
if [ "${RELEASE_NO_JARS:-0}" != "1" ] && have aeb; then
  say "building the Java jars (crossbuild + package) …"
  # aeb resolves node labels repo-root-relative, so run it from ROOT with relative paths.
  if ( cd "$ROOT" && aeb selenium_core/.crossbuild.ae java/.package.ae ) >"$DIST/.jars.log" 2>&1; then
    jdir="$ROOT/target/package/java"
    for j in "$jdir"/selenium-client.jar "$jdir"/selenium-client-standalone.jar "$jdir"/selenium-client-"$(uname -s | tr 'A-Z' 'a-z' | sed 's/darwin/macos/;s/.*linux.*/linux/')-$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')".jar; do
      [ -f "$j" ] || continue
      cp "$j" "$DIST/"
      ( cd "$DIST" && sha256sum "$(basename "$j")" > "$(basename "$j").sha256" )
      say "  jar: $(basename "$j") ($(du -h "$j" | cut -f1)) staged + .sha256"
    done
    rm -f "$DIST/.jars.log"
  else
    say "SKIP jars — aeb build failed (engine libs still ship); see $DIST/.jars.log"
  fi
elif [ "${RELEASE_NO_JARS:-0}" != "1" ]; then
  say "SKIP jars — aeb not on PATH (engine libs still ship)"
fi

# A combined checksum manifest over every artifact (not the .sha256 sidecars).
# Named SHA256SUMS.txt so a browser renders it inline (no forced download).
( cd "$DIST" && sha256sum ./*.so ./*.dylib ./*.dll ./*.dll.lib ./*.jar 2>/dev/null > SHA256SUMS.txt || true )

echo
say "built $built engine artifact(s) into release/dist/ ($failed failed)"
if [ "$built" -gt 0 ]; then
  echo
  ( cd "$DIST" && for f in *.so *.dylib *.dll *.jar; do [ -f "$f" ] && printf '  %s  %s\n' "$(cut -c1-16 "$f.sha256")…" "$f"; done ) 2>/dev/null
  echo
  say "each artifact has a .sha256; SHA256SUMS.txt lists them all."
  say "next: attest on real hardware — run the binding suite against a given"
  say "      artifact on its target box and record 'sha256 X passed' (see release/README.md)."
fi
[ "$failed" -eq 0 ] || exit 1
