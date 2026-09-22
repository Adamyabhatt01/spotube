#!/usr/bin/env bash
#
# Install or update this fork's Linux build with one command:
#
#   bash scripts/install-local.sh
#
# Re-running is the upgrade path: it rebuilds, backs up the previous install,
# replaces it in place and refreshes the menu entry. Nothing needs uninstalling.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKIP_BUILD=0
PREFIX=""

usage() {
  sed -n '3,7p' "${BASH_SOURCE[0]}" | cut -c3-
  cat <<'EOF'
Options:
  -s, --skip-build     Install the bundle that is already in build/linux/
  -p, --prefix DIR     Install here (default: auto-detected)
  -h, --help           This menu
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  -s | --skip-build) SKIP_BUILD=1 ;;
  -p | --prefix)
    PREFIX="${2:?--prefix needs a directory}"
    shift
    ;;
  -h | --help | "")
    usage
    exit 0
    ;;
  *)
    echo "Unknown option: $1" >&2
    usage >&2
    exit 1
    ;;
  esac
  shift
done

run_flutter() {
  if command -v fvm >/dev/null 2>&1 && [[ -e "$REPO/.fvm" || -e "$REPO/.fvmrc" ]]; then
    (cd "$REPO" && fvm flutter "$@")
  elif command -v flutter >/dev/null 2>&1; then
    (cd "$REPO" && flutter "$@")
  else
    echo "No 'flutter' (or 'fvm flutter') on PATH. Install the Flutter SDK first." >&2
    exit 1
  fi
}

if [[ -z $PREFIX ]]; then
  # Prefer a writable system location so all users get the build, but never
  # require root: fall back to the per-user dir.
  if [[ -w /usr/local/share/spotube-custom || -w /usr/local/share ]]; then
    PREFIX=/usr/local/share/spotube-custom
  else
    PREFIX="$HOME/.local/share/spotube-custom"
  fi
fi

if ((SKIP_BUILD == 0)); then
  echo "==> Building release Linux bundle"
  run_flutter build linux --release
fi

arch=$(uname -m)
case "$arch" in
x86_64) flutter_arch=x64 ;;
aarch64 | arm64) flutter_arch=arm64 ;;
*) flutter_arch="$arch" ;;
esac

BUNDLE="$REPO/build/linux/$flutter_arch/release/bundle"
if [[ ! -f "$BUNDLE/spotube" ]]; then
  # A differently-named output dir is common after a manual -v/--target-platform run.
  BUNDLE="$(find "$REPO/build/linux" -maxdepth 3 -type d -name bundle 2>/dev/null | sort | tail -1)"
fi
if [[ ! -f "$BUNDLE/spotube" ]]; then
  echo "No built bundle found under build/linux/*/release/bundle. Drop --skip-build." >&2
  exit 1
fi

DEST="$PREFIX"
if [[ -f "$DEST/lib/libapp.so" ]] &&
  cmp -s "$DEST/lib/libapp.so" "$BUNDLE/lib/libapp.so"; then
  echo "==> Already up to date: $DEST"
else
  if [[ -f "$DEST/spotube" ]]; then
    BK="$HOME/spotube-local-backup-$(date +%Y%m%d-%H%M%S).tar"
    echo "==> Backing up $DEST -> $BK"
    tar -C "$(dirname "$DEST")" -cf "$BK" "$(basename "$DEST")"
  fi
  echo "==> Installing $BUNDLE -> $DEST"
  mkdir -p "$DEST"
  # --remove-destination unlinks first, so replacing the files of a running
  # instance does not fail with ETXTBSY.
  cp -a --remove-destination "$BUNDLE/." "$DEST/"
fi

BIN="$DEST/spotube"
chmod +x "$BIN"

if [[ $DEST == "$HOME"* ]]; then
  mkdir -p "$HOME/.local/bin"
  ln -sfn "$BIN" "$HOME/.local/bin/spotube"
  case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "  NOTE: add ~/.local/bin to PATH to get the 'spotube' command." ;;
  esac
elif [[ ! -e /usr/local/bin/spotube && -w /usr/local/bin ]]; then
  ln -sfn "$BIN" /usr/local/bin/spotube
fi

ICON="$DEST/data/flutter_assets/assets/branding/spotube-logo.png"
[[ -f $ICON ]] || ICON="spotube"

# A user entry shadows the system one of the same filename, so the existing
# menu icon starts this build without touching any package-owned file.
DESK_DIR="$HOME/.local/share/applications"
mkdir -p "$DESK_DIR"
cat >"$DESK_DIR/spotube.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Spotube
GenericName=Music Player
Exec=$BIN %u
Icon=$ICON
Comment=Music streaming app combining metadata providers and YouTube (local build)
Terminal=false
Categories=Audio;Music;Player;AudioVideo;
StartupWMClass=spotube
EOF
command -v update-desktop-database >/dev/null 2>&1 &&
  update-desktop-database "$DESK_DIR" 2>/dev/null || true

# Matched in-shell: piping ldconfig into 'grep -q' makes grep exit on the first
# hit, and the resulting SIGPIPE looks like a failed lookup under pipefail.
LDCACHE="$(ldconfig -p 2>/dev/null || true)"
missing=()
softmissing=()
for lib in libmpv.so.2 libsecret-1.so.0; do
  [[ $LDCACHE == *$lib* ]] || missing+=("$lib")
done
# Only affects the system tray icon, so it is reported separately.
[[ $LDCACHE == *libappindicator3.so.1* ]] || softmissing+=(libappindicator3.so.1)

if ((${#missing[@]})); then
  echo "  WARNING: missing shared libraries: ${missing[*]}"
  echo "  Arch: sudo pacman -S mpv libsecret"
  echo "  Debian/Ubuntu: sudo apt install libmpv2 libsecret-1-0"
fi
if ((${#softmissing[@]})); then
  echo "  NOTE: no ${softmissing[*]} - the tray icon will be unavailable."
fi

echo
echo "Done."
echo "  binary  : $BIN"
echo "  menu    : $DESK_DIR/spotube.desktop"
if pgrep -x spotube >/dev/null 2>&1; then
  echo "  Spotube is running - quit and relaunch it to use the new build."
else
  echo "  launch  : $BIN"
fi
