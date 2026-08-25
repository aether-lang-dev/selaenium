#!/usr/bin/env bash
# Groovy binding: compile the Java FFM binding classes, then run the Groovy test
# with the Java classes + groovy/src on the classpath. The Groovy layer is pure
# Java-interop over the one JVM binding — no second FFI.
#
# Toolchain reality: the Java binding is Panama FFM (JDK 22+). Debian's Groovy
# 2.4 runs on JVM 17 and can't read JDK-22+ bytecode, so we need a modern Groovy
# (>= 4) on a JDK >= 22. Discovery order:
#   1. $GROOVY_HOME/bin/groovy
#   2. ~/.sdkman/candidates/groovy/current/bin/groovy
#   3. a `groovy` on PATH THAT IS >= 4
# SKIPS LOUDLY (exit 0) when none is found.
# Args: <engine .so path> <java-src-dir> <groovy-dir>
set -u
ENGINE="${1:?}"; JAVA_SRC="${2:?}"; GDIR="${3:?}"

find_groovy() {
  if [ -n "${GROOVY_HOME:-}" ] && [ -x "$GROOVY_HOME/bin/groovy" ]; then echo "$GROOVY_HOME/bin/groovy"; return 0; fi
  local sdk="$HOME/.sdkman/candidates/groovy/current/bin/groovy"
  if [ -x "$sdk" ]; then echo "$sdk"; return 0; fi
  if command -v groovy >/dev/null 2>&1; then
    local v; v="$(groovy --version 2>&1 | grep -oE 'Groovy Version: [0-9]+' | grep -oE '[0-9]+' | head -1)"
    if [ -n "$v" ] && [ "$v" -ge 4 ]; then command -v groovy; return 0; fi
  fi
  return 1
}

GROOVY="$(find_groovy)" || {
  echo "groovy tests: SKIPPED — no Groovy >= 4 on a JDK >= 22 found (Debian's 2.4/JVM17 can't read the FFM binding; set GROOVY_HOME or install via sdkman)"
  exit 0
}

JOUT="$GDIR/jout"
rm -rf "$JOUT"; mkdir -p "$JOUT"
javac -d "$JOUT" "$JAVA_SRC"/*.java || { echo "groovy tests: javac (Java binding) FAILED"; exit 1; }

# --enable-native-access via JAVA_OPTS (groovy forwards it to the JVM).
SELENIUM_CORE_LIB="$ENGINE" \
  JAVA_OPTS="--enable-native-access=ALL-UNNAMED" \
  "$GROOVY" -cp "$JOUT:$GDIR/src" "$GDIR/test/live_test.groovy"
