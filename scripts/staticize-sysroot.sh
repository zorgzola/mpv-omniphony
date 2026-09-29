#!/usr/bin/env bash
# Convert the MinGW cross sysroot to STATIC-ONLY so the mpv link below produces
# a single static mpv.exe (the ~120MB official-style single-file build).
#
# Three jobs:
#   1. Remove the dependency DLLs + import libs so `-lfoo` can only resolve to
#      libfoo.a. The two intentional dynamic imports stay: vulkan-1.dll (the
#      Vulkan ICD loader, kept external like every static mpv build) and
#      orender.dll (the Omniphony spatial-audio renderer plugin, kept external).
#   2. Map the packages Martchus ships shared-only (.pc points at *-shared) to
#      their static archives: shaderc -> shaderc_combined, spirv-cross-* ->
#      the per-module static pieces.
#   3. Flatten every pkg-config file: rewrite `Libs:` to the full
#      `pkg-config --static --libs <mod>` output (expands Requires.private /
#      Libs.private recursively). Meson links pkg-config deps using only the
#      `Libs` line, so without this a static link misses the transitive closure
#      and dies with undefined references.
#
# Must run AFTER all deps are installed/built into $SYS and BEFORE the mpv link.
#
# Env:
#   SYS   MinGW sysroot / install prefix (default /usr/x86_64-w64-mingw32)
set -euo pipefail

SYS="${SYS:-/usr/x86_64-w64-mingw32}"
PKGCONFIG="x86_64-w64-mingw32-pkg-config"
command -v python3 >/dev/null || { echo "!! staticize needs python3 for the .pc rewrite" >&2; exit 1; }

echo ">> staticize sysroot: $SYS"

# ---------------------------------------------------------------------------
# 1. Runtime DLLs that stay external (dynamic imports / dlopen targets).
# ---------------------------------------------------------------------------
KEEP_DLL='^vulkan-1\.dll$|^orender\.dll$'
find "$SYS/bin" -maxdepth 1 -type f -name '*.dll' 2>/dev/null | sort | while read -r f; do
  base="$(basename "$f")"
  if echo "$base" | grep -qE "$KEEP_DLL"; then
    echo "  keep dll : $base"
  else
    rm -f "$f"
    echo "  - $base"
  fi
done

# ---------------------------------------------------------------------------
# 2. Import libraries: strip all but the two intentional dynamic imports.
#    (orender has no .dll.a — its .pc points at the bare DLL in lib/, which
#    meson resolves directly; the rule still guards if that ever changes.)
# ---------------------------------------------------------------------------
KEEP_IMPORT='^liborender\.dll\.a$|^libvulkan-1\.dll\.a$'
find "$SYS/lib" -maxdepth 1 -type f -name '*.dll.a' 2>/dev/null | sort | while read -r f; do
  base="$(basename "$f")"
  if echo "$base" | grep -qE "$KEEP_IMPORT"; then
    echo "  keep import: $base"
  else
    rm -f "$f"
    echo "  - $base"
  fi
done

# ---------------------------------------------------------------------------
# 3. Shared-only -> static archive mappings (applied on every flattened Libs).
#    Martchus's shaderc/spirv-cross .pc point at the -shared DLLs, but the
#    static archives exist; remap so the static link picks them up.
# ---------------------------------------------------------------------------
STATIC_MAP=(
  '-lshaderc_shared|-lshaderc_combined'
  '-lspirv-cross-c-shared|-lspirv-cross-c -lspirv-cross-cpp -lspirv-cross-hlsl -lspirv-cross-glsl -lspirv-cross-util -lspirv-cross-reflect -lspirv-cross-msl -lspirv-cross-core'
)

# ---------------------------------------------------------------------------
# 4. Flatten every .pc in the sysroot.
# ---------------------------------------------------------------------------
shopt -s nullglob
for pc in "$SYS"/lib/pkgconfig/*.pc; do
  mod="$(basename "$pc" .pc)"
  libs="$("$PKGCONFIG" --static --libs "$mod" 2>/dev/null)" || {
    echo "!! pkg-config --static --libs $mod failed (missing Requires.private dep?)" >&2
    exit 1
  }
  for pair in "${STATIC_MAP[@]}"; do
    old="${pair%%|*}"
    new="${pair#*|}"
    libs="${libs//$old/$new}"
  done
  python3 - "$pc" "$libs" <<'PY'
import sys
pc, libs = sys.argv[1], sys.argv[2]
lines = open(pc, encoding='utf-8').read().splitlines()
out, rewritten = [], False
for ln in lines:
    if ln.startswith('Libs:'):
        out.append('Libs: ' + libs.strip())
        rewritten = True
    elif ln.startswith('Libs.private:'):
        continue  # now folded into Libs
    else:
        out.append(ln)
if not rewritten:
    out.append('Libs: ' + libs.strip())
open(pc, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
print("  flat: " + mod)
PY
done

# ---------------------------------------------------------------------------
# 5. Sanity: every -l<name> a flattened Libs emits must resolve inside the
#    sysroot (static .a, kept import lib, or bare DLL) or be a known Windows
#    system library.
# ---------------------------------------------------------------------------
KNOWN_SYSTEM='gdi32|user32|kernel32|advapi32|shell32|ole32|oleaut32|ws2_32|imm32|version|winmm|d3d11|dxgi|d3dcompiler_47|opengl32|setupapi|rpcrt4|bcrypt|crypt32|comdlg32|netapi32|powrprof|psapi|userenv|wininet|wintrust|comctl32|iphlpapi|secur32|uxtheme|dwmapi|ncrypt|dnsapi|mpr|mswsock|odbc32|odbccp32|uuid|mingw32|mingwex|mingwthrd|m|pthread|winpthread|gcc|gcc_eh|stdc\+\+'
for pc in "$SYS"/lib/pkgconfig/*.pc; do
  mod="$(basename "$pc" .pc)"
  libs="$("$PKGCONFIG" --libs "$mod" 2>/dev/null || true)"
  for tok in $libs; do
    case "$tok" in
      -L*) continue ;;
      -l*) name="${tok#-l}" ;;
      *) continue ;;
    esac
    echo "$name" | grep -qE "$KNOWN_SYSTEM" && continue
    # Strip trailing .a-style version suffixes like -lharfbuzz-subset -> exact.
    if [ -f "$SYS/lib/lib${name}.a" ] || [ -f "$SYS/lib/lib${name}.dll.a" ] \
       || [ -f "$SYS/lib/${name}.dll" ] || [ -f "$SYS/lib/lib${name}.dll" ]; then
      continue
    fi
    echo "!! $mod: -l${name} resolves to nothing under $SYS/lib" >&2
    exit 1
  done
done

echo "OK: sysroot staticized (external DLLs: $(ls "$SYS"/bin/*.dll 2>/dev/null | xargs -n1 basename 2>/dev/null | tr '\n' ' '))"
