#!/usr/bin/env bash
set -euo pipefail

# Run from the repository root with full Git history and companion release tags.
destination="${1:-artifacts/companion-release}"
mkdir -p "$destination"
cliff=(git-cliff --config .github/companion-cliff.toml)
"${cliff[@]}" --unreleased --context > "$destination/context.json"
if [[ "$(jq '[.[].commits[]] | length' "$destination/context.json")" == 0 ]]; then
  echo 'No unreleased companion changes.'
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then echo 'has_changes=false' >> "$GITHUB_OUTPUT"; fi
  exit 0
fi

tag="$("${cliff[@]}" --bumped-version)"
if [[ ! "$tag" =~ ^companion-v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "Invalid companion release tag: $tag" >&2
  exit 1
fi
version="${tag#companion-v}"
"${cliff[@]}" --bump --output "$destination/CHANGELOG.md"
"${cliff[@]}" --bump --unreleased --output "$destination/release-notes.md"
printf '%s\n' "$version" > "$destination/version.txt"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'has_changes=true\ntag=%s\nversion=%s\n' "$tag" "$version" >> "$GITHUB_OUTPUT"
fi
echo "Prepared $tag in $destination"
