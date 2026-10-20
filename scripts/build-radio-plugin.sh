#!/usr/bin/env bash
#
# Build the Hetu directory plugins into the bundled `.smplug` assets the app
# auto-installs on first launch.
#
#   scripts/build-radio-plugin.sh                 # every plugins/*/
#   scripts/build-radio-plugin.sh internet-radio-browser [...]
#
# A `.smplug` is a zip of `plugin.json` + `plugin.out` (+ `logo.png` when the
# plugin ships one), where `plugin.out` is Hetu bytecode compiled from
# `src/plugin.ht` by the pinned `hetu_script_dev_tools` CLI.
#
# The CLI is run through its kernel snapshot rather than the `hetu` global
# wrapper, because that wrapper execs a bare `dart` which is not on PATH here.
# Snapshots are SDK-version tagged, so the one matching `fvm dart` is picked.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

dart_version="$(fvm dart --version 2>&1 | sed -E 's/.*Dart SDK version: ([0-9.]+).*/\1/')"
snapshot="$HOME/.pub-cache/global_packages/hetu_script_dev_tools/bin/cli_tool.dart-${dart_version}.snapshot"

if [[ ! -f "$snapshot" ]]; then
  echo "error: no hetu compiler snapshot for Dart ${dart_version}" >&2
  echo "       expected ${snapshot}" >&2
  echo "       install with: fvm dart pub global activate hetu_script_dev_tools" >&2
  exit 1
fi

build_one() {
  local plugin_dir="$1"
  local source="${plugin_dir}/src/plugin.ht"
  local manifest="${plugin_dir}/plugin.json"

  [[ -f "$source" && -f "$manifest" ]] || {
    echo "skip ${plugin_dir}: no src/plugin.ht or plugin.json"
    return
  }

  # Same slug the plugin loader derives for its extraction directory.
  local name slug out_dir staged
  name="$(grep -m1 '"name"' "$manifest" | sed -E 's/.*"name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
  slug="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-//; s/-$//')"
  out_dir="assets/plugins/spotube-plugin-${slug}"
  staged="${plugin_dir}/build"

  rm -rf "$staged"
  mkdir -p "$staged" "$out_dir"

  fvm dart "$snapshot" compile "$source" "${staged}/plugin.out"
  cp "$manifest" "${staged}/plugin.json"

  local entries=("${staged}/plugin.json" "${staged}/plugin.out")
  [[ -f "${plugin_dir}/logo.png" ]] && entries+=("${plugin_dir}/logo.png")

  fvm dart run scripts/plugin_zip.dart "${out_dir}/plugin.smplug" "${entries[@]}"

  echo "built ${out_dir}/plugin.smplug"
}

if [[ $# -gt 0 ]]; then
  for plugin in "$@"; do
    build_one "plugins/${plugin}"
  done
else
  for dir in plugins/*/; do
    build_one "${dir%/}"
  done
fi
