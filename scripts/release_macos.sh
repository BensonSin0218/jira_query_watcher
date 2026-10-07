#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  printf 'release_macos.sh: %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

for command_name in awk codesign curl ditto gh git security spctl unzip xcodebuild xmllint; do
  require_command "$command_name"
done

RUN_TESTS="${RUN_TESTS:-1}"
if [[ "$RUN_TESTS" == "1" ]]; then
  require_command fvm
fi

version_line="$(awk '$1 == "version:" { print $2; exit }' pubspec.yaml)"
[[ -n "$version_line" ]] || fail "version is missing from pubspec.yaml"
[[ "$version_line" == *+* ]] || fail "version must include a build number, for example 1.2.3+4"

VERSION="${version_line%%+*}"
BUILD_NUMBER="${version_line##*+}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "invalid semantic version: $VERSION"
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || fail "invalid build number: $BUILD_NUMBER"

BRANCH="$(git symbolic-ref --short HEAD)"
[[ "$BRANCH" == "main" ]] || fail "release must run from main, current branch: $BRANCH"
[[ -z "$(git status --porcelain)" ]] || fail "working tree is not clean; commit current changes before releasing"

git fetch origin main --quiet
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "local main is not synced with origin/main"

ORIGIN_URL="$(git config --get remote.origin.url || true)"
if [[ -n "${REPO_SLUG:-}" ]]; then
  :
elif [[ "$ORIGIN_URL" == git@github.com:* ]]; then
  REPO_SLUG="${ORIGIN_URL#git@github.com:}"
elif [[ "$ORIGIN_URL" == https://github.com/* ]]; then
  REPO_SLUG="${ORIGIN_URL#https://github.com/}"
elif [[ "$ORIGIN_URL" == ssh://git@github.com/* ]]; then
  REPO_SLUG="${ORIGIN_URL#ssh://git@github.com/}"
else
  fail "origin is not a GitHub repository: $ORIGIN_URL"
fi
REPO_SLUG="${REPO_SLUG%.git}"
[[ "$REPO_SLUG" == */* ]] || fail "unable to determine GitHub repository: $REPO_SLUG"

RELEASE_TAG="v$VERSION"
if gh release view "$RELEASE_TAG" --repo "$REPO_SLUG" >/dev/null 2>&1; then
  fail "GitHub release already exists: $RELEASE_TAG"
fi
if git ls-remote --exit-code origin "refs/tags/$RELEASE_TAG" >/dev/null 2>&1; then
  fail "Git tag already exists: $RELEASE_TAG"
fi

FLUTTER_VERSION="${FLUTTER_VERSION:-3.44.9}"
FVM_HOME="${FVM_HOME:-$HOME/fvm}"
FLUTTER_ROOT="${FLUTTER_ROOT:-$FVM_HOME/versions/$FLUTTER_VERSION}"
[[ -x "$FLUTTER_ROOT/bin/flutter" ]] || fail "Flutter SDK not found: $FLUTTER_ROOT"

MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-12.0}"
NOTARY_PROFILE="${NOTARY_PROFILE:-jira-query-watcher-notary}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-ed25519}"
SPARKLE_BIN="${SPARKLE_BIN:-$ROOT_DIR/macos/Pods/Sparkle/bin}"
SIGN_UPDATE="$SPARKLE_BIN/sign_update"
GENERATE_APPCAST="$SPARKLE_BIN/generate_appcast"
[[ -x "$SIGN_UPDATE" ]] || fail "Sparkle sign_update not found: $SIGN_UPDATE"
[[ -x "$GENERATE_APPCAST" ]] || fail "Sparkle generate_appcast not found: $GENERATE_APPCAST"

if [[ -z "${SIGNING_IDENTITY:-}" ]]; then
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning | awk -F '"' '/Developer ID Application/ { print $2; exit }')"
fi
[[ -n "$SIGNING_IDENTITY" ]] || fail "no Developer ID Application identity found"

if [[ -z "${DOWNLOAD_URL_PREFIX:-}" ]]; then
  DOWNLOAD_URL_PREFIX="https://github.com/$REPO_SLUG/releases/latest/download/"
fi

if [[ "$RUN_TESTS" == "1" ]]; then
  fvm flutter analyze
  fvm flutter test
  [[ -z "$(git status --porcelain)" ]] || fail "tests modified tracked files; inspect before releasing"
fi

RELEASE_DIR="$ROOT_DIR/build/macos-$VERSION"
FLUTTER_BUILD_DIR="build-macos-$VERSION"
APP="$RELEASE_DIR/Build/Products/Release/Jira Query Watcher.app"
ZIP="$RELEASE_DIR/Jira-Query-Watcher-$VERSION.zip"

xcodebuild \
  -workspace "$ROOT_DIR/macos/Runner.xcworkspace" \
  -scheme Runner \
  -configuration Release \
  -derivedDataPath "$RELEASE_DIR" \
  -sdk macosx \
  FLUTTER_ROOT="$FLUTTER_ROOT" \
  FLUTTER_BUILD_DIR="$FLUTTER_BUILD_DIR" \
  FLUTTER_BUILD_NAME="$VERSION" \
  FLUTTER_BUILD_NUMBER="$BUILD_NUMBER" \
  MACOSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  ENABLE_HARDENED_RUNTIME=NO \
  build

[[ -d "$APP" ]] || fail "built app not found: $APP"

SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERSION="$SPARKLE/Versions/B"
ENTITLEMENTS="$ROOT_DIR/macos/Runner/Release.entitlements"

codesign --force --verbose --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$SPARKLE_VERSION/XPCServices/Installer.xpc"
codesign --force --verbose --sign "$SIGNING_IDENTITY" --options runtime --timestamp --preserve-metadata=entitlements "$SPARKLE_VERSION/XPCServices/Downloader.xpc"
codesign --force --verbose --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$SPARKLE_VERSION/Autoupdate"
codesign --force --verbose --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$SPARKLE_VERSION/Updater.app"
codesign --force --verbose --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$SPARKLE"

shopt -s nullglob
for framework in "$APP/Contents/Frameworks/"*.framework; do
  [[ "$framework" == "$SPARKLE" ]] || codesign --force --verbose --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$framework"
done

codesign --force --verbose --sign "$SIGNING_IDENTITY" --options runtime --timestamp --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict "$APP"

rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
unzip -t "$ZIP" >/dev/null
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"

rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
unzip -t "$ZIP" >/dev/null

SIGNATURE="$("$SIGN_UPDATE" --account "$SPARKLE_ACCOUNT" -p "$ZIP")"
[[ -n "$SIGNATURE" ]] || fail "Sparkle signature is empty"
"$SIGN_UPDATE" --account "$SPARKLE_ACCOUNT" --verify "$ZIP" "$SIGNATURE"

"$GENERATE_APPCAST" \
  --account "$SPARKLE_ACCOUNT" \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  -o "$ROOT_DIR/appcast.xml" \
  "$RELEASE_DIR"
xmllint --noout "$ROOT_DIR/appcast.xml"

if ! git diff --quiet -- appcast.xml; then
  git add appcast.xml
  git commit -m "$(cat <<EOF
Update Sparkle appcast for $VERSION.

Generated with [Devin](https://devin.ai)

Co-Authored-By: Devin <158243242+devin-ai-integration[bot]@users.noreply.github.com>
EOF
)"
  git push origin main
fi

gh release create "$RELEASE_TAG" \
  "$ZIP" \
  "$ROOT_DIR/appcast.xml" \
  --repo "$REPO_SLUG" \
  --target main \
  --title "Jira Query Watcher $VERSION" \
  --notes "macOS release. Signed with Developer ID Application, notarized, stapled, and published with Sparkle EdDSA metadata. Build $BUILD_NUMBER."

curl -L -f -sS -o /dev/null "${DOWNLOAD_URL_PREFIX}Jira-Query-Watcher-$VERSION.zip"
curl -L -f -sS -o /dev/null "${DOWNLOAD_URL_PREFIX}appcast.xml"

printf '%s\n' "Release published: https://github.com/$REPO_SLUG/releases/tag/$RELEASE_TAG"
printf '%s\n' "Archive: $ZIP"
printf '%s\n' "Appcast: $ROOT_DIR/appcast.xml"
