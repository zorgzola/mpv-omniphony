#!/usr/bin/env bash
# Build libdvdread + libdvdnav STATICALLY from source into the MinGW cross
# sysroot. Martchus ships them only as DLLs (no .a — checked 2026-09-29), so a
# fully-static mpv.exe must rebuild them static. DVD folder + ISO playback stays:
# libdvdread reads disc images natively (UDF/ISO9660), same as the Martchus DLL.
#
# Versions: upstream videolan 6.1.x autotools releases (latest 6.x line;
# tarballs ship a pre-generated configure, so no autoreconf needed).
#
# Env:
#   SYS   MinGW sysroot / install prefix (default /usr/x86_64-w64-mingw32)
set -euo pipefail

SYS="${SYS:-/usr/x86_64-w64-mingw32}"
HOST=x86_64-w64-mingw32
JOBS="${JOBS:-$(nproc)}"
DVDREAD_VER=6.1.3
DVDNAV_VER=6.1.1

log(){ printf '\n>> %s\n' "$*"; }
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cd "$work"

# --- libdvdread (static) -----------------------------------------------------
if [ ! -f "$SYS/lib/libdvdread.a" ]; then
  log "libdvdread $DVDREAD_VER (static)"
  curl -fsSL -o dvdread.tar.bz2 \
    "https://download.videolan.org/pub/videolan/libdvdread/${DVDREAD_VER}/libdvdread-${DVDREAD_VER}.tar.bz2"
  tar xf dvdread.tar.bz2
  ( cd "libdvdread-${DVDREAD_VER}" && \
    ./configure --host="${HOST}" --prefix="$SYS" \
      --disable-shared --enable-static --disable-doc --disable-apidoc )
  make -C "libdvdread-${DVDREAD_VER}" -j"$JOBS"
  make -C "libdvdread-${DVDREAD_VER}" install
else
  log "libdvdread static already present"
fi

# --- libdvdnav (static) ------------------------------------------------------
if [ ! -f "$SYS/lib/libdvdnav.a" ]; then
  log "libdvdnav $DVDNAV_VER (static)"
  curl -fsSL -o dvdnav.tar.bz2 \
    "https://download.videolan.org/pub/videolan/libdvdnav/${DVDNAV_VER}/libdvdnav-${DVDNAV_VER}.tar.bz2"
  tar xf dvdnav.tar.bz2
  ( cd "libdvdnav-${DVDNAV_VER}" && \
    PKG_CONFIG_PATH="$SYS/lib/pkgconfig" \
    ./configure --host="${HOST}" --prefix="$SYS" \
      --disable-shared --enable-static --disable-doc )
  make -C "libdvdnav-${DVDNAV_VER}" -j"$JOBS"
  make -C "libdvdnav-${DVDNAV_VER}" install
else
  log "libdvdnav static already present"
fi

# --- verify ---------------------------------------------------------------
"${HOST}-pkg-config" --exists dvdread  || { echo "!! dvdread.pc not visible to ${HOST}-pkg-config" >&2; exit 1; }
"${HOST}-pkg-config" --exists dvdnav   || { echo "!! dvdnav.pc not visible to ${HOST}-pkg-config"  >&2; exit 1; }
test -f "$SYS/lib/libdvdread.a" || { echo "!! $SYS/lib/libdvdread.a missing" >&2; exit 1; }
test -f "$SYS/lib/libdvdnav.a"  || { echo "!! $SYS/lib/libdvdnav.a missing"  >&2; exit 1; }
log "OK: libdvdread + libdvdnav static installed"
