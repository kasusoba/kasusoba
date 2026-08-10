#!/usr/bin/env bash
set -euo pipefail

REPO="MelonThug/genius-annotations"
APP_NAME="genius-annotations"

# --- colors (only when attached to a terminal) -------------------------------
if [ -t 1 ]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; RESET=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; RESET=""
fi

updating=false
tmp_dir=""

cleanup() { [ -n "$tmp_dir" ] && rm -rf "$tmp_dir"; }
fail() {
  printf '%sError during installation%s\n' "$RED" "$RESET" >&2
  printf 'Installation aborted.\n' >&2
  exit 1
}
trap cleanup EXIT
trap fail ERR

# --- locate spicetify --------------------------------------------------------
if ! command -v spicetify >/dev/null 2>&1; then
  printf '%sspicetify was not found in PATH.%s\n' "$RED" "$RESET" >&2
  printf 'Install it first: https://spicetify.app/docs/getting-started\n' >&2
  exit 1
fi

# `spicetify -c` prints the path to config-xpui.ini; CustomApps lives beside it.
config_file="$(spicetify -c)"
spicetify_dir="$(dirname "$config_file")"
custom_apps_dir="$spicetify_dir/CustomApps"
target_dir="$custom_apps_dir/$APP_NAME"

mkdir -p "$custom_apps_dir"

tmp_dir="$(mktemp -d)"
zip_file="$tmp_dir/$APP_NAME.zip"
extract_dir="$tmp_dir/extract"

# --- fetch latest release ----------------------------------------------------
printf 'Fetching latest release from GitHub...\n'
release_json="$(curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$REPO/releases/latest")"

if command -v jq >/dev/null 2>&1; then
  release_url="$(printf '%s' "$release_json" | jq -r '.assets[0].browser_download_url')"
  tag_name="$(printf '%s' "$release_json" | jq -r '.tag_name')"
elif command -v python3 >/dev/null 2>&1; then
  read -r release_url tag_name <<EOF
$(printf '%s' "$release_json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["assets"][0]["browser_download_url"], d["tag_name"])')
EOF
else
  release_url="$(printf '%s' "$release_json" | grep -o '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 1 | cut -d'"' -f4)"
  tag_name="$(printf '%s' "$release_json" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 1 | cut -d'"' -f4)"
fi

if [ -z "${release_url:-}" ] || [ "$release_url" = "null" ]; then
  printf '%sCould not find a downloadable asset in the latest release.%s\n' "$RED" "$RESET" >&2
  exit 1
fi

# --- download & extract ------------------------------------------------------
printf 'Downloading %s %s...\n' "$APP_NAME" "$tag_name"
curl -fsSL "$release_url" -o "$zip_file"

mkdir -p "$extract_dir"
unzip -qo "$zip_file" -d "$extract_dir"

# If the archive wraps everything in a single folder, use that folder's contents.
shopt -s nullglob
entries=("$extract_dir"/*)
shopt -u nullglob
if [ "${#entries[@]}" -eq 1 ] && [ -d "${entries[0]}" ]; then
  extract_dir="${entries[0]}"
fi

# --- install -----------------------------------------------------------------
if [ -d "$target_dir" ] && [ -n "$(ls -A "$target_dir" 2>/dev/null)" ]; then
  printf '%sWarning%s "%s" Found existing install. Removing...\n' "$YELLOW" "$RESET" "$target_dir"
  rm -rf "${target_dir:?}"/* "${target_dir:?}"/.[!.]* 2>/dev/null || true
  updating=true
fi

mkdir -p "$target_dir"
cp -R "$extract_dir"/. "$target_dir"/

spicetify config custom_apps "$APP_NAME"
spicetify apply

printf '%ssuccess%s ' "$GREEN" "$RESET"
if [ "$updating" = true ]; then
  printf '%s successfully updated to %s!\n' "$APP_NAME" "$tag_name"
else
  printf '%s %s installation complete!\n' "$APP_NAME" "$tag_name"
fi
