#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_VERSION="${TEXTLENS_VERSION:-$(cat "$ROOT_DIR/VERSION")}"
if [[ ! "$APP_VERSION" =~ ^[0-9]+(\.[0-9]+){2}$ ]]; then
	printf 'Error: TEXTLENS_VERSION must be a three-part numeric version (for example, 0.1.0); got: %s\n' "$APP_VERSION" >&2
	exit 1
fi

SIGNING_IDENTITY="${CODESIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-TextLensNotary}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/TextLens.app"
FINAL_ZIP="$DIST_DIR/TextLens-${APP_VERSION}.zip"

path_exists() {
	[[ -e "$1" || -L "$1" ]]
}

check_final_paths() {
	local phase="$1"
	if path_exists "$FINAL_ZIP"; then
		printf 'Error: release ZIP already exists during %s; refusing to overwrite it: %s\n' \
			"$phase" "$FINAL_ZIP" >&2
		return 1
	fi
}

mkdir -p "$DIST_DIR"
if ! check_final_paths preflight; then
	exit 1
fi

IDENTITIES="$(/usr/bin/security find-identity -v -p codesigning 2>&1)" || {
	printf 'Error: could not query available code-signing identities.\n%s\n' "$IDENTITIES" >&2
	exit 1
}
if [[ -z "$SIGNING_IDENTITY" ]]; then
	SIGNING_IDENTITY="$(printf '%s\n' "$IDENTITIES" | /usr/bin/awk -F '"' '/Developer ID Application:/ { print $2; exit }')"
fi
if [[ -z "$SIGNING_IDENTITY" ]]; then
	printf 'Error: no Developer ID Application identity found. Set CODESIGN_IDENTITY or install a certificate.\n' >&2
	exit 1
fi
if ! printf '%s\n' "$IDENTITIES" | /usr/bin/grep -Fq "$SIGNING_IDENTITY"; then
	printf 'Error: required signing identity is unavailable: %s\nAvailable identities:\n%s\n' \
		"$SIGNING_IDENTITY" "$IDENTITIES" >&2
	exit 1
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format json >/dev/null 2>&1; then
	printf 'Error: notarytool profile %s is unavailable or could not authenticate. Configure or repair it with xcrun notarytool store-credentials.\n' \
		"$NOTARY_PROFILE" >&2
	exit 1
fi

TEMP_DIR="$(/usr/bin/mktemp -d "$DIST_DIR/.textlens-release.XXXXXX")"
cleanup() {
	local exit_status=$?
	trap - EXIT
	if [[ -n "$TEMP_DIR" ]]; then
		case "$TEMP_DIR" in
			"$DIST_DIR"/.textlens-release.*)
				if [[ -d "$TEMP_DIR" ]] && ! /bin/rm -rf "$TEMP_DIR"; then
					printf 'Error: could not remove temporary release staging directory: %s\n' "$TEMP_DIR" >&2
					exit_status=1
				fi
				;;
			*)
				printf 'Error: refusing to remove unexpected temporary path: %s\n' "$TEMP_DIR" >&2
				exit_status=1
				;;
		esac
	fi
	exit "$exit_status"
}
trap cleanup EXIT

PRE_NOTARIZATION_ZIP="$TEMP_DIR/TextLens-pre-notarization.zip"
STAGED_ZIP="$TEMP_DIR/TextLens-${APP_VERSION}.zip"

TEXTLENS_VERSION="$APP_VERSION" "$ROOT_DIR/scripts/build-app.sh"

/usr/bin/codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_DIR"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"

/usr/bin/ditto -c -k --keepParent "$APP_DIR" "$PRE_NOTARIZATION_ZIP"
if ! xcrun notarytool submit "$PRE_NOTARIZATION_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait; then
	printf 'Error: Apple notarization failed for %s.\n' "$APP_DIR" >&2
	exit 1
fi

xcrun stapler staple "$APP_DIR"
xcrun stapler validate "$APP_DIR"

/usr/bin/ditto -c -k --keepParent "$APP_DIR" "$STAGED_ZIP"

if ! check_final_paths publication; then
	exit 1
fi

if ! /bin/mv -n "$STAGED_ZIP" "$FINAL_ZIP" || path_exists "$STAGED_ZIP"; then
	printf 'Error: could not publish the release ZIP without overwriting an existing path: %s\n' "$FINAL_ZIP" >&2
	exit 1
fi

ZIP_SHA256="$(/usr/bin/shasum -a 256 "$FINAL_ZIP" | /usr/bin/awk '{print $1}')"
printf 'Created release archive: %s\nSHA-256: %s\n' "$FINAL_ZIP" "$ZIP_SHA256"
