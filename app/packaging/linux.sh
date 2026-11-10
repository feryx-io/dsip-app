#!/usr/bin/env bash
# The Linux installers from a release bundle (Anvil's app/packaging/linux.sh is the model): a .deb (installed in
# /opt/dsip, `dsip` on the path) and an AppImage (one file, runs in place). Needs dpkg-deb, and appimagetool with the
# type2 runtime (paths in APPIMAGETOOL and APPIMAGE_RUNTIME).
#
#   packaging/linux.sh <version> <label> <bundle dir> <out dir>
set -euo pipefail
umask 022

version=$1 label=$2 bundle=$3 out=$4
here=$(cd "$(dirname "$0")" && pwd)
app=$(cd "$here/.." && pwd)
repo=$(cd "$app/.." && pwd)
id=com.feryx.dsip
mkdir -p "$out"
work=$(mktemp -d)

# --- .deb -----------------------------------------------------------------------------------------------------------
root="$work/deb"
mkdir -p "$root/DEBIAN" "$root/opt/dsip" "$root/usr/bin" "$root/usr/share/applications" \
  "$root/usr/share/icons/hicolor/512x512/apps" "$root/usr/share/doc/dsip"
cp -a "$bundle/." "$root/opt/dsip/"
ln -s /opt/dsip/dsip "$root/usr/bin/dsip"
cp "$app/linux/packaging/dsip.desktop" "$root/usr/share/applications/$id.desktop"
cp "$app/linux/packaging/dsip.png" "$root/usr/share/icons/hicolor/512x512/apps/$id.png"
cat "$repo/LICENSE-MIT" "$repo/LICENSE-APACHE" "$app/assets/fonts/OFL.txt" > "$root/usr/share/doc/dsip/copyright"
cat > "$root/DEBIAN/control" <<CONTROL
Package: dsip
Version: $version
Architecture: amd64
Maintainer: DSIP <noreply@github.com>
Homepage: https://github.com/feryx-io/dsip-app
Section: net
Priority: optional
Installed-Size: $(du -sk "$root/opt" | cut -f1)
Depends: libgtk-3-0t64 | libgtk-3-0, libasound2t64 | libasound2
Description: DSIP: calls, messages and presence from an identity you hold
 Your identity is a key on this device, not an account on a server. Calls
 through a relay, end-to-end encrypted messages through a mailbox, and
 presence shared with those you choose.
CONTROL
dpkg-deb --root-owner-group --build "$root" "$out/dsip_${label}_amd64.deb"

# --- AppImage -------------------------------------------------------------------------------------------------------
appdir="$work/DSIP.AppDir"
mkdir -p "$appdir/usr/lib/dsip"
cp -a "$bundle/." "$appdir/usr/lib/dsip/"
cat > "$appdir/AppRun" <<'APPRUN'
#!/bin/sh
here="$(dirname "$(readlink -f "$0")")"
exec "$here/usr/lib/dsip/dsip" "$@"
APPRUN
chmod +x "$appdir/AppRun"
cp "$app/linux/packaging/dsip.desktop" "$appdir/$id.desktop"
cp "$app/linux/packaging/dsip.png" "$appdir/$id.png"
ARCH=x86_64 VERSION=$version "$APPIMAGETOOL" --no-appstream \
  --runtime-file "$APPIMAGE_RUNTIME" "$appdir" "$out/DSIP-${label}-x86_64.AppImage"

ls -l "$out"
