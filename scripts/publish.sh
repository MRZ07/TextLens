#!/bin/bash
set -euo pipefail

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

[[ $# -le 1 ]] || fail "Usage: scripts/publish.sh [release-notes.md]"
notes=(--generate-notes)
if [[ $# -eq 1 ]]; then
    [[ -f "$1" ]] || fail "Release notes file not found: $1"
    notes=(--notes-file "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")")
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

REPO="MRZ07/TextLens"
BRANCH="main"
CASK="Casks/textlens.rb"
APP_VERSION="$(cat VERSION)"
version_pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
[[ "$APP_VERSION" =~ $version_pattern ]] || fail "VERSION must be a three-part release version."

TAG="v$APP_VERSION"
ASSET="TextLens-$APP_VERSION.zip"
ASSET_URL="https://github.com/$REPO/releases/download/$TAG/$ASSET"
ARCHIVE="$ROOT_DIR/dist/$ASSET"
BUILD_SOURCE="$ROOT_DIR/dist/.publish-$TAG-source"

[[ "$(git branch --show-current)" == "$BRANCH" ]] || fail "Run from the main branch."
[[ -z "$(git status --porcelain)" ]] || fail "Commit the app changes and VERSION before publishing."
for remote_url in "$(git remote get-url origin)" "$(git remote get-url --push --all origin)"; do
    case "$remote_url" in
        "git@github.com:$REPO.git"|"https://github.com/$REPO.git"|"https://github.com/$REPO") ;;
        *) fail "origin must point to github.com/$REPO." ;;
    esac
done
git fetch origin "$BRANCH" --tags
git merge-base --is-ancestor "origin/$BRANCH" HEAD || fail "Sync main with origin/main before publishing."
case "$(gh repo view "$REPO" --json viewerPermission --jq .viewerPermission)" in
    ADMIN|MAINTAIN|WRITE) ;;
    *) fail "The GitHub CLI account needs write access to $REPO." ;;
esac

checksum() {
    /usr/bin/shasum -a 256 "$1" | awk '{print $1}'
}

cask_value() {
    sed -nE "s/^  $1 \"([^\"]+)\"$/\1/p" "$CASK"
}

cask_version="$(cask_value version)"
[[ "$cask_version" =~ $version_pattern ]] || fail "Could not read the current cask version from $CASK."
if [[ "$cask_version" != "$APP_VERSION" ]]; then
    # Compare version components numerically so 0.10.0 sorts after 0.9.0.
    awk -v new="$APP_VERSION" -v old="$cask_version" 'BEGIN {
        split(new, n, ".")
        split(old, o, ".")
        for (i = 1; i <= 3; i++) {
            if (n[i]+0 > o[i]+0) exit 0
            if (n[i]+0 < o[i]+0) exit 1
        }
        exit 1
    }' || fail "VERSION must be newer than the cask version ($cask_version)."
    if git show-ref --verify --quiet "refs/tags/$TAG"; then
        fail "$TAG already exists. Choose a new version."
    fi

    swift test
    mkdir -p dist
    source_commit="$(git rev-parse HEAD)"
    if [[ -e "$ARCHIVE" ]]; then
        [[ -f "$BUILD_SOURCE" && "$(cat "$BUILD_SOURCE")" == "$source_commit" ]] ||
            fail "An archive already exists for a different build. Move it aside and rerun."
    else
        printf '%s\n' "$source_commit" > "$BUILD_SOURCE"
        TEXTLENS_VERSION="$APP_VERSION" "$ROOT_DIR/scripts/package-release.sh"
    fi

    expected_checksum="$(checksum "$ARCHIVE")"
    [[ "$(cask_value sha256)" =~ ^[0-9a-f]{64}$ ]] || fail "Could not read the cask checksum."
    sed -i '' -E \
        -e "s/^  version \"[^\"]+\"$/  version \"$APP_VERSION\"/" \
        -e "s/^  sha256 \"[^\"]+\"$/  sha256 \"$expected_checksum\"/" "$CASK"
    git diff --check -- "$CASK"
    git add -- "$CASK"
    git commit -m "chore(release): publish textlens $APP_VERSION"
fi

expected_checksum="$(cask_value sha256)"
[[ "$expected_checksum" =~ ^[0-9a-f]{64}$ ]] || fail "Could not read the cask checksum."
head="$(git rev-parse HEAD)"
if git show-ref --verify --quiet "refs/tags/$TAG"; then
    [[ "$(git rev-list -n 1 "$TAG")" == "$head" ]] ||
        fail "$TAG points to a different commit. Advance VERSION for a new release."
fi

# A release already published by an interrupted run can be verified without a local ZIP.
draft_status="$(gh api --paginate "repos/$REPO/releases" \
    --jq ".[] | select(.tag_name == \"$TAG\") | .draft")"

if [[ "$draft_status" != false ]]; then
    [[ -f "$ARCHIVE" && "$(checksum "$ARCHIVE")" == "$expected_checksum" ]] ||
        fail "$ASSET is missing or its checksum differs from the cask."
fi

if ! git show-ref --verify --quiet "refs/tags/$TAG"; then
    [[ -z "$draft_status" ]] || fail "GitHub has a release for $TAG without a matching local tag."
    git tag -a "$TAG" -m "TextLens $APP_VERSION"
fi
git push origin "refs/tags/$TAG"

if [[ -z "$draft_status" ]]; then
    gh release create "$TAG" --repo "$REPO" --verify-tag --draft \
        --title "TextLens $APP_VERSION" "${notes[@]}"
    draft_status=true
fi

if [[ "$draft_status" == true ]]; then
    asset_state="$(gh release view "$TAG" --repo "$REPO" --json assets \
        --jq ".assets[] | select(.name == \"$ASSET\") | .state")"
    if [[ -z "$asset_state" ]]; then
        gh release upload "$TAG" "$ARCHIVE" --repo "$REPO"
    else
        [[ "$asset_state" == uploaded ]] || fail "The draft contains an incomplete asset. Remove it and rerun."
    fi

    verification_dir="$(mktemp -d)"
    trap 'rm -rf -- "$verification_dir"' EXIT
    gh release download "$TAG" --repo "$REPO" --pattern "$ASSET" --dir "$verification_dir"
    [[ "$(checksum "$verification_dir/$ASSET")" == "$expected_checksum" ]] ||
        fail "The draft asset differs from the cask checksum."
    gh release edit "$TAG" --repo "$REPO" --draft=false --latest --verify-tag
fi

# Keep the tap on the previous cask until the public asset is available and verified.
public_archive="$(mktemp)"
trap 'rm -f -- "$public_archive"; if [[ -n "${verification_dir:-}" ]]; then rm -rf -- "$verification_dir"; fi' EXIT
curl --fail --silent --show-error --location --retry 3 --output "$public_archive" "$ASSET_URL"
[[ "$(checksum "$public_archive")" == "$expected_checksum" ]] ||
    fail "The public download differs from the cask checksum."
git push origin "HEAD:refs/heads/$BRANCH"
printf 'Published TextLens %s and updated the Homebrew cask.\n%s\n' \
    "$APP_VERSION" "https://github.com/$REPO/releases/tag/$TAG"
