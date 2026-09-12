#!/usr/bin/env bash
set -euo pipefail

# Run from the repository root with full Git history and companion release tags.
destination="${1:-artifacts/companion-release}"
mkdir -p "$destination"
cliff=(git-cliff --config .github/companion-cliff.toml)
# git-cliff's include_paths drops tags on empty merges and unrelated commits.
# Skip their changelog entries instead, preserving every release boundary.
paths=(
  'Companion/**' 'Shared/Sounds/**' 'Riff/Resources/sound-packs.json'
  'scripts/build-windows.ps1' 'scripts/prepare-companion-release.sh'
  'scripts/test-companion-release.py'
  '.github/workflows/companion.yml' '.github/companion-cliff.toml'
  'docs/WINDOWS-QUICKSTART.txt' 'docs/THIRD-PARTY.md' 'docs/licenses/**'
  'global.json' 'NuGet.Config' 'nuget.config'
  'Directory.Build.props' 'Directory.Build.targets' 'Directory.Packages.props'
)
git rev-list HEAD | LC_ALL=C sort > "$destination/all-commits.txt"
git log --full-history --diff-merges=first-parent --format=%H -- "${paths[@]}" |
  LC_ALL=C sort -u > "$destination/companion-commits.txt"
LC_ALL=C comm -23 "$destination/all-commits.txt" "$destination/companion-commits.txt" > "$destination/skipped-commits.txt"
while IFS= read -r commit; do cliff+=(--skip-commit "$commit"); done < "$destination/skipped-commits.txt"
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
if git show-ref --verify --quiet "refs/tags/$tag"; then
  echo "Release tag $tag already exists despite unreleased companion changes." >&2
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
