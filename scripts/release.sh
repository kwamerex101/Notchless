#!/usr/bin/env bash
#
# release.sh — build, deep-sign, notarize, staple, and package Notchless for
# distribution. Encapsulates the manual steps from the v1.2.1 notarization so a
# release is one command.
#
# Why the deep re-sign: a plain `xcodebuild build` product is NOT notarizable —
# it has no secure timestamp, keeps the debug `get-task-allow` entitlement, and
# never re-signs the bundled MediaRemoteAdapter.framework (a folder resource,
# still carrying the upstream author's cert). We re-sign every nested framework
# and the app with --options runtime --timestamp and our entitlements file
# (which omits get-task-allow), then submit to Apple.
#
# Usage:
#   scripts/release.sh                 # build → sign → notarize → staple → dist/Notchless-<ver>.zip
#   scripts/release.sh --install       # also replace /Applications/Notchless.app
#   scripts/release.sh --release       # also create/update the GitHub release for tag v<ver>
#   scripts/release.sh --no-notarize   # build + deep-sign only (skip Apple submission)
#
# Env overrides:
#   SIGN_ID=<sha1>          codesign identity hash (default: first "Developer ID
#                           Application" in the keychain — set this if you have
#                           more than one with the same name, as HOMEKARE does)
#   NOTARY_PROFILE=<name>   notarytool keychain profile (default: ListenToMe)

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

PROJECT="Notchless.xcodeproj"
SCHEME="Notchless"
ENTITLEMENTS="Resources/Notchless.entitlements"
NOTARY_PROFILE="${NOTARY_PROFILE:-ListenToMe}"

INSTALL=false
RELEASE=false
NOTARIZE=true
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=true ;;
    --release) RELEASE=true ;;
    --no-notarize) NOTARIZE=false ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
die()  { printf '\033[1;31merror: %s\033[0m\n' "$1" >&2; exit 1; }

# ---- 0. Resolve version + signing identity -------------------------------
VERSION="$(awk -F'"' '/MARKETING_VERSION:/{print $2; exit}' project.yml)"
[ -n "$VERSION" ] || die "could not read MARKETING_VERSION from project.yml"
step "Releasing Notchless v$VERSION"

SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning \
  | awk '/Developer ID Application/{print $2; exit}')}"
[ -n "$SIGN_ID" ] || die "no 'Developer ID Application' codesigning identity found"
echo "signing identity: $SIGN_ID"

# ---- 1. Generate + build Release -----------------------------------------
step "Regenerating project and building Release"
xcodegen generate >/dev/null
xcodebuild build \
  -project "$PROJECT" -scheme "$SCHEME" \
  -configuration Release -destination 'platform=macOS' \
  -skipMacroValidation \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true

BUILT_APP="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -configuration Release -showBuildSettings -skipMacroValidation 2>/dev/null \
  | awk -F' = ' '/ CODESIGNING_FOLDER_PATH/{print $2; exit}')"
[ -d "$BUILT_APP" ] || die "built app not found (build failed?)"
echo "built: $BUILT_APP"

# ---- 2. Stage a copy + deep re-sign --------------------------------------
step "Deep re-signing (runtime + timestamp, no get-task-allow)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/Notchless.app"
cp -R "$BUILT_APP" "$APP"

# Every nested framework, deepest first, then the app bundle last so its seal
# covers the fresh nested signatures.
while IFS= read -r fw; do
  echo "  sign $(basename "$fw")"
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$fw"
done < <(find "$APP/Contents" -name '*.framework' -type d | awk '{print gsub(/\//,"/"), $0}' | sort -rn | cut -d' ' -f2-)

codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" --sign "$SIGN_ID" "$APP"

# ---- 3. Verify the signature is notarization-ready -----------------------
# Capture into variables and match with `case` — piping into `grep -q` under
# `set -o pipefail` SIGPIPEs codesign and yields false pass/fail results.
step "Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -1
ENTS="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -p - 2>/dev/null || true)"
case "$ENTS" in *get-task-allow*) die "get-task-allow still present" ;; esac
SIGINFO="$(codesign -dvv "$APP" 2>&1 || true)"
case "$SIGINFO" in *Timestamp=*) : ;; *) die "no secure timestamp" ;; esac
echo "ok: valid, no get-task-allow, timestamped"

DIST="$ROOT/dist"; mkdir -p "$DIST"
ZIP="$DIST/Notchless-$VERSION.zip"

# ---- 4. Notarize + staple -------------------------------------------------
if $NOTARIZE; then
  security find-generic-password -s "com.apple.gke.notary.tool.saved-creds" \
    -a "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || die "notary profile '$NOTARY_PROFILE' not found. Create it once with:
  xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id <email> --team-id <TEAMID> --password <app-specific-pw>"

  step "Submitting to Apple notary service (waits for verdict)"
  rm -f "$ZIP"; ditto -c -k --keepParent "$APP" "$ZIP"
  SUB_ID="$(xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait \
    2>&1 | tee /dev/stderr | awk '/^  id:/{id=$2} /status: Accepted/{ok=1} END{if(ok)print id}')"
  if [ -z "$SUB_ID" ]; then
    LAST_ID="$(xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" 2>/dev/null | awk '/id:/{print $2; exit}')"
    echo "--- notarization failed; fetching log ---" >&2
    [ -n "$LAST_ID" ] && xcrun notarytool log "$LAST_ID" --keychain-profile "$NOTARY_PROFILE" >&2 || true
    die "notarization was not Accepted"
  fi

  step "Stapling ticket"
  xcrun stapler staple "$APP"
  spctl -a -vvv "$APP" 2>&1 | grep -E "source=|accepted|rejected" || true

  # Re-zip the STAPLED app so the distributed archive validates offline.
  rm -f "$ZIP"; ditto -c -k --keepParent "$APP" "$ZIP"
else
  step "Skipping notarization (--no-notarize)"
  rm -f "$ZIP"; ditto -c -k --keepParent "$APP" "$ZIP"
fi
echo "packaged: $ZIP"

# ---- 5. Optional: install + GitHub release --------------------------------
if $INSTALL; then
  step "Installing to /Applications"
  pkill -x Notchless 2>/dev/null || true
  sleep 1
  rm -rf /Applications/Notchless.app
  cp -R "$APP" /Applications/Notchless.app
  echo "installed /Applications/Notchless.app (v$VERSION)"
fi

if $RELEASE; then
  step "Creating/updating GitHub release v$VERSION"
  # Pull this version's section out of CHANGELOG.md for the notes.
  NOTES="$(awk -v v="## [$VERSION]" '
    index($0,v)==1{p=1; next}
    p && /^## \[/{exit}
    p{print}' CHANGELOG.md)"
  if gh release view "v$VERSION" >/dev/null 2>&1; then
    gh release upload "v$VERSION" "$ZIP" --clobber
  else
    git tag -f "v$VERSION" && git push -f origin "v$VERSION"
    gh release create "v$VERSION" "$ZIP" --title "v$VERSION" --notes "${NOTES:-Release v$VERSION}"
  fi
fi

step "Done — v$VERSION"
