#!/usr/bin/env bash
# Kotlin binding: compile the Java FFM binding classes + the Kotlin idiomatic
# wrapper + the test, then run against the engine. The Kotlin layer is pure
# Java-interop over the one JVM binding — no second FFI.
#
# Toolchain reality: the Java binding is Panama FFM (JDK 22+), so its classes are
# JDK-22+ bytecode. Debian's kotlinc 1.3 CANNOT read that (`Unsupported class
# file major version`), so we need a modern kotlinc. Discovery order:
#   1. $KOTLIN_HOME/bin/kotlinc
#   2. ~/.sdkman/candidates/kotlin/current/bin/kotlinc  (this box)
#   3. a `kotlinc` on PATH THAT IS >= 1.9 (Debian's 1.3 is rejected)
# SKIPS LOUDLY (exit 0) when no capable Kotlin is found.
# Args: <engine .so path> <java-src-dir> <kotlin-dir>
set -u
ENGINE="${1:?}"; JAVA_SRC="${2:?}"; KDIR="${3:?}"

find_kotlinc() {
  if [ -n "${KOTLIN_HOME:-}" ] && [ -x "$KOTLIN_HOME/bin/kotlinc" ]; then
    echo "$KOTLIN_HOME/bin/kotlinc"; return 0
  fi
  local sdk="$HOME/.sdkman/candidates/kotlin/current/bin/kotlinc"
  if [ -x "$sdk" ]; then echo "$sdk"; return 0; fi
  if command -v kotlinc >/dev/null 2>&1; then
    local v; v="$(kotlinc -version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)"
    local major="${v%%.*}"; local minor="${v#*.}"
    if [ "$major" -gt 1 ] || { [ "$major" -eq 1 ] && [ "$minor" -ge 9 ]; }; then
      command -v kotlinc; return 0
    fi
  fi
  return 1
}

KOTLINC="$(find_kotlinc)" || {
  echo "kotlin tests: SKIPPED — no Kotlin >= 1.9 found (Debian's 1.3 can't read the JDK 22+ FFM binding; set KOTLIN_HOME or install via sdkman)"
  exit 0
}
KHOME="$(dirname "$(dirname "$KOTLINC")")"
STDLIB="$KHOME/lib/kotlin-stdlib.jar"

OUT="$KDIR/out"
JOUT="$KDIR/jout"
rm -rf "$OUT" "$JOUT"; mkdir -p "$OUT" "$JOUT"

# Compile the Java FFM binding classes.
javac -d "$JOUT" "$JAVA_SRC"/*.java || { echo "kotlin tests: javac (Java binding) FAILED"; exit 1; }
# Compile the Kotlin wrapper + test against them.
"$KOTLINC" -cp "$JOUT" -d "$OUT" \
  "$KDIR/src/main/kotlin/org/seleniumhq/aether/kotlin/SeleniumCore.kt" \
  "$KDIR/src/test/kotlin/org/seleniumhq/aether/kotlin/LiveTest.kt" \
  || { echo "kotlin tests: kotlinc FAILED"; exit 1; }

SELENIUM_CORE_LIB="$ENGINE" \
  java --enable-native-access=ALL-UNNAMED \
  -cp "$JOUT:$OUT:$STDLIB" \
  org.seleniumhq.aether.kotlin.LiveTestKt
