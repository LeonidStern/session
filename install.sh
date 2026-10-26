#!/bin/sh
#
#   Session - install.sh
#   Copyright (c) 2026 Leonid Stern. All rights reserved.
#
#   Installs or updates the Session VST3 plug-in on macOS or Linux, from the
#   newest build or from a release candidate:
#
#     curl -fsSL https://raw.githubusercontent.com/LeonidStern/session/main/install.sh | sh
#     curl -fsSL https://raw.githubusercontent.com/LeonidStern/session/main/install.sh | sh -s rc0.2
#
#   macOS: ~/Library/Audio/Plug-Ins/VST3 (the Mac build is signed with a Developer ID and
#   notarized; the script checks the signature before installing). Linux: ~/.vst3.
#   Nothing needs sudo. Rescan plug-ins in your DAW afterwards.

set -eu

REPO="LeonidStern/session"
TAG="${1:-latest}"
NAME="Session.vst3"
OLD_NAME="O11Session.vst3" # its name before 2026-10-26

case "$(uname -s)" in
  Darwin)
    case "$(uname -m)" in
      arm64) FILE="Session-macos-arm64.zip" ;;
      x86_64) FILE="Session-macos-x86_64.zip" ;;
      *) echo "Session: no Mac build for $(uname -m)" >&2; exit 1 ;;
    esac
    DEST="$HOME/Library/Audio/Plug-Ins/VST3"
    ;;
  Linux)
    case "$(uname -m)" in
      x86_64) FILE="Session-linux-x86_64.zip" ;;
      *) echo "Session: no Linux build for $(uname -m)" >&2; exit 1 ;;
    esac
    DEST="$HOME/.vst3"
    command -v unzip >/dev/null 2>&1 || { echo "Session: please install unzip first" >&2; exit 1; }
    ;;
  *)
    echo "Session: this script is for macOS and Linux; on Windows use the zip from the README" >&2
    exit 1
    ;;
esac

URL="https://github.com/$REPO/releases/download/$TAG/$FILE"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Downloading $FILE ($TAG)"
curl -fL --progress-bar -o "$WORK/$FILE" "$URL" || { echo "Session: couldn't download $URL" >&2; exit 1; }

mkdir -p "$WORK/x"
if [ "$(uname -s)" = Darwin ]; then
  # ditto keeps the bundle's signature and stapled ticket intact
  ditto -x -k "$WORK/$FILE" "$WORK/x"
else
  unzip -q "$WORK/$FILE" -d "$WORK/x"
fi
NEW="$(find "$WORK/x" -maxdepth 2 -name "$NAME" -type d | head -1)"
[ -n "$NEW" ] || { echo "Session: $NAME isn't in $FILE" >&2; exit 1; }

if [ "$(uname -s)" = Darwin ]; then
  # not --strict: the bundle carries Finder's bundle bit (an extended attribute) on purpose,
  # which --strict rejects; the signature over the files inside is what this checks
  codesign --verify --deep "$NEW" || { echo "Session: the download's signature doesn't check out; not installing it" >&2; exit 1; }
  SIGNER="$(codesign -dvv "$NEW" 2>&1 | sed -n 's/^Authority=\(Developer ID Application:.*\)/\1/p' | head -1)"
  echo "Signed by: ${SIGNER:-ad hoc (not notarized)}"
fi

mkdir -p "$DEST"
# the old copy goes only once the new one is in place beside it
rm -rf "$DEST/$NAME.new"
mv "$NEW" "$DEST/$NAME.new"
rm -rf "$DEST/$NAME"
mv "$DEST/$NAME.new" "$DEST/$NAME"

rm -rf "$DEST/$OLD_NAME"

echo "Installed $DEST/$NAME"
# the disk image puts it in the computer-wide folder; two copies confuse a DAW
for OLD in "$NAME" "$OLD_NAME"; do
  if [ "$(uname -s)" = Darwin ] && [ -d "/Library/Audio/Plug-Ins/VST3/$OLD" ]; then
    echo "An older copy is in /Library/Audio/Plug-Ins/VST3; remove it so your DAW loads this one:"
    echo "  sudo rm -rf \"/Library/Audio/Plug-Ins/VST3/$OLD\""
  fi
done
echo "Rescan plug-ins in your DAW (in Ableton: Settings, Plug-Ins, Rescan)."
