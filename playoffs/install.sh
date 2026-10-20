#!/bin/sh
set -eu

# This small, uncached selector keeps the public command stable while the
# installer and its downloaded archive remain pinned to one immutable release.
# Pin a Play-owned installer (0.4.105 or earlier); later Play releases only
# hand off to rote. That installer runs rote's installer, which would install a
# second, rote-owned Play; ROTE_NO_PLAY stops it.
release=v0.4.105

curl --proto '=https' --tlsv1.2 -fsSL \
  "https://raw.githubusercontent.com/modiqo/play/${release}/install.sh" \
  | env PLAY_INSTALL_REF="${release}" PLAY_INSTALL_CHANNEL=playoffs ROTE_NO_PLAY=1 sh -s -- "$@"
