#!/bin/bash
# Linux launcher shim for the mpv-omniphony FEL + BD-J build.
#
# This file sits next to mpv-bin in the same directory (usually the root of
# the unpacked zip). Its job: resolve the bundled share/libbluray paths
# relative to IT (NOT the caller's $PWD) and export the three env vars
# libbluray probes BEFORE it dlopen()s the bundled JVM:
#
#   BLURAY_JVM_LIB_PATH   absolute path to libjvm.so (strongest override,
#                         bypasses dlopen heuristics)
#   LIBBLURAY_CP          absolute path to the VERSIONED j2se jar (e.g.
#                         libbluray-j2se-1.5.1.jar). This value is read FIRST
#                         in libbluray src/libbluray/bdj/bdj.c:556 via getenv.
#                         CRITICAL: the value MUST be the versioned jar name
#                         because libbluray _find_libbluray_jar1() reconstructs
#                         the sibling AWT jar filename by slicing
#                           cut = len(jar0) - len(VERSION) - 9
#                         and inserting "awt-" at the cut; if we pass the plain
#                         libbluray.jar name here, cut <= 0, awt jar lookup
#                         returns NULL, which in turn frees the main jar too,
#                         producing the infamous "libbluray.jar: 0" diagnostic.
#   JAVA_HOME             set to the bundled jre directory when unset so any
#                         fallback probes in libbluray that only know JAVA_HOME
#                         still find the bundled runtime.
#
# Users who want to use their own JDK/JRE can pre-set those env vars; we skip
# overwriting BLURAY_JVM_LIB_PATH / JAVA_HOME when they're already set.
# LIBBLURAY_CP is always pointed at the bundled versioned j2se jar because
# that jar was compiled with the exact meson/jdk from this CI build and the
# native ABI on the C side must match.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
RES="$(cd "$HERE/share/libbluray" 2>/dev/null && pwd)" || RES=""

# ---------------- bundled JVM path -----------------------------------------
# jlink on Linux puts libjvm at jre/lib/server/libjvm.so; some non-jlink JDK
# layouts ship the entry library at jre/lib/jli/libjli.so. Cover both. When
# the caller already pinned BLURAY_JVM_LIB_PATH externally, keep their value.
if [ -z "${BLURAY_JVM_LIB_PATH:-}" ] && [ -n "$RES" ]; then
  if   [ -f "$RES/jre/lib/server/libjvm.so" ]; then
    export BLURAY_JVM_LIB_PATH="$RES/jre/lib/server/libjvm.so"
  elif [ -f "$RES/jre/lib/jli/libjli.so" ]; then
    export BLURAY_JVM_LIB_PATH="$RES/jre/lib/jli/libjli.so"
  fi
fi

# ---------------- bundled jar path (LIBBLURAY_CP) --------------------------
# Find the meson-produced VERSIONED j2se jar. If the versioned jar is absent,
# fall back to the plain libbluray.jar copy (with a diagnostic).
if [ -n "$RES" ]; then
  J2SE_JAR="$(ls "$RES"/libbluray-j2se-*.jar 2>/dev/null | head -1 || true)"
  if [ -n "$J2SE_JAR" ] && [ -f "$J2SE_JAR" ]; then
    export LIBBLURAY_CP="$J2SE_JAR"
  elif [ -f "$RES/libbluray.jar" ]; then
    echo "[mpv-bdj-launcher] WARNING: versioned libbluray-j2se-*.jar missing; falling back to plain $RES/libbluray.jar (this will likely still report libbluray.jar=0 due to _find_libbluray_jar1 string slicing)." >&2
    export LIBBLURAY_CP="$RES/libbluray.jar"
  fi
fi

# ---------------- JAVA_HOME fallback ---------------------------------------
if [ -z "${JAVA_HOME:-}" ] && [ -n "$RES" ] && [ -d "$RES/jre" ]; then
  export JAVA_HOME="$RES/jre"
fi

exec "$HERE/mpv-bin" "$@"
