#!/usr/bin/env bash
# The macOS disk image from a release build: DSIP.app beside a link to Applications, to drag across.
#
#   packaging/macos.sh <label> <DSIP.app> <out dir>
set -euo pipefail
umask 022

label=$1 app=$2 out=$3
mkdir -p "$out"
stage=$(mktemp -d)/DSIP
mkdir -p "$stage"
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "DSIP" -srcfolder "$stage" -ov -format UDZO "$out/DSIP-${label}-macos.dmg"
ls -l "$out"
