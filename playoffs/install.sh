#!/bin/sh
set -eu

# This small, uncached selector keeps the public command stable while the
# installer and its downloaded archive remain pinned to one immutable release.
release=v0.4.93

curl --proto '=https' --tlsv1.2 -fsSL \
  "https://raw.githubusercontent.com/modiqo/play/${release}/install.sh" \
  | env PLAY_INSTALL_REF="${release}" PLAY_INSTALL_CHANNEL=playoffs sh -s -- "$@"
