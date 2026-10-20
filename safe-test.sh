#!/usr/bin/env bash
# Safe flutter test — prevents Hyprland OOM-logout.
# - forces low concurrency (default 2, not 16)
# - runs isolated from hyprland.service cgroup via systemd-run,
#   so even if a test OOMs, Hyprland survives and only the test dies.
# Usage:
#   ./safe-test.sh                          # full suite, concurrency 2
#   ./safe-test.sh test/foo_test.dart       # single file
#   ./safe-test.sh -c 1 test/foo_test.dart  # custom concurrency
#   ./safe-test.sh -c 1 -- --plain-name "foo"  # extra flutter args after --
set -u

CONCURRENCY=2
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--concurrency) CONCURRENCY="$2"; shift 2 ;;
    --) shift; while [[ $# -gt 0 ]]; do ARGS+=("$1"); shift; done ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

cd "$(dirname "$0")"

echo "=> flutter test --concurrency=$CONCURRENCY ${ARGS[*]:-"(all)"} (isolated scope)"
exec systemd-run --user --scope --quiet -- \
  fvm flutter test --concurrency="$CONCURRENCY" "${ARGS[@]}"
