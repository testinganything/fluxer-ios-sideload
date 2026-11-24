#!/usr/bin/env bash
# Zip build/ios/iphoneos/*.app into an unsigned sideloadable IPA.
# Run from the flutter_client checkout root, after `flutter build ios --no-codesign`.
set -euo pipefail

STRIP_EXTENSIONS="${STRIP_EXTENSIONS:-true}"
DIST_DIR="${DIST_DIR:-${GITHUB_WORKSPACE:-.}/dist}"
FLAVOR="${FLAVOR:-unknown}"
mkdir -p "${DIST_DIR}"

if [[ ! -d build/ios/iphoneos ]]; then
  echo "::error::build/ios/iphoneos does not exist. The Flutter iOS build did not produce a device app."
  exit 1
fi

APP=""
while IFS= read -r candidate; do
  APP="${candidate}"
  break
done < <(find build/ios/iphoneos -type d -name '*.app' \
  -not -path '*/PlugIns/*' \
  -not -path '*/Watch/*' \
  -not -path '*/Frameworks/*')

if [[ -z "${APP}" || ! -d "${APP}" ]]; then
  echo "::error::No application bundle under build/ios/iphoneos"
  find build/ios -type d -name '*.app' || true
  exit 1
fi

echo "Packaging ${APP}"

if [[ "${STRIP_EXTENSIONS}" == "true" ]]; then
  rm -rf "${APP}/PlugIns" "${APP}/Extensions" "${APP}/Watch"
  echo "Removed PlugIns (share, notification service, broadcast). A free Apple ID can install the main app."
fi

# Truly unsigned: no signature blob and no embedded provisioning profile.
while IFS= read -r sig; do
  rm -rf "${sig}"
done < <(find "${APP}" -type d -name '_CodeSignature')
while IFS= read -r profile; do
  rm -f "${profile}"
done < <(find "${APP}" -type f -name '*.mobileprovision')
rm -f "${APP}/embedded.mobileprovision"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Info.plist")"
BUILD_NUM="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${APP}/Info.plist")"
BUNDLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${APP}/Info.plist")"
if /usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "${APP}/Info.plist" >/dev/null 2>&1; then
  DISPLAY="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "${APP}/Info.plist")"
else
  DISPLAY="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "${APP}/Info.plist")"
fi

SHA="$(git rev-parse HEAD)"
SHORT_SHA="$(git rev-parse --short=12 HEAD)"
SAFE_BUNDLE="${BUNDLE//./-}"
IPA_NAME="Fluxer-${VERSION}-${SAFE_BUNDLE}-unsigned.ipa"

STAGE="$(mktemp -d)"
mkdir -p "${STAGE}/Payload"
# BSD cp -R keeps symlinks inside Flutter.framework. zip -y stores them as links.
cp -R "${APP}" "${STAGE}/Payload/"

# Xcode's linker may leave an ad-hoc signature. Strip it before zipping so the
# IPA is actually unsigned. Sideloadly re-signs either way. A real Apple
# Development or Distribution identity means signing was not turned off.
PAYLOAD_APP="${STAGE}/Payload/$(basename "${APP}")"

strip_macho() {
  local target="$1"
  if [[ -f "${target}" ]] && file "${target}" 2>/dev/null | grep -q 'Mach-O'; then
    codesign --remove-signature "${target}" 2>/dev/null || true
  fi
}

EXE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${PAYLOAD_APP}/Info.plist")"
strip_macho "${PAYLOAD_APP}/${EXE_NAME}"
while IFS= read -r macho; do
  strip_macho "${macho}"
done < <(find "${PAYLOAD_APP}" -type f)

SIGN_INFO="$(codesign -dv "${PAYLOAD_APP}" 2>&1 || true)"
echo "${SIGN_INFO}"
case "${SIGN_INFO}" in
  *"not signed"*)
    echo "Confirmed unsigned app bundle."
    ;;
  *"Signature=adhoc"*|*adhoc*)
    echo "Bundle is ad-hoc signed only (no Apple certificate). Sideload tools can re-sign it."
    ;;
  *"Authority="*)
    echo "::error::App is signed by an Apple certificate. Refusing to publish it as unsigned."
    exit 1
    ;;
  *)
    echo "codesign did not report an Apple certificate. Continuing."
    ;;
esac

(
  cd "${STAGE}"
  zip -r -y -q "${DIST_DIR}/${IPA_NAME}" Payload
)

UPSTREAM="https://github.com/fluxerapp/flutter_client"
cat > "${DIST_DIR}/BUILD_INFO.txt" <<EOF
Fluxer unsigned iOS build
App: ${DISPLAY}
Bundle ID: ${BUNDLE}
Version: ${VERSION} (${BUILD_NUM})
Flavor: ${FLAVOR}
Extensions removed: ${STRIP_EXTENSIONS}
Upstream: ${UPSTREAM}
Commit: ${SHA}
${UPSTREAM}/commit/${SHA}
Built: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Builder: https://github.com/${GITHUB_REPOSITORY:-local}

This file is an unsigned IPA of the official open-source Fluxer client.
It is not signed by Fluxer Platform AB, it is not a TestFlight build, and it
will not install if you tap it. Sign it with your own Apple ID (Sideloadly,
SideStore, or AltStore) or install it with TrollStore on a supported iOS.

Corresponding AGPLv3 source for this binary:
${UPSTREAM}/tree/${SHA}
EOF

if [[ -f ios/Runner/Runner.entitlements ]]; then
  cp ios/Runner/Runner.entitlements "${DIST_DIR}/Runner.entitlements"
fi

ls -lh "${DIST_DIR}/${IPA_NAME}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "ipa_name=${IPA_NAME}"
    echo "version=${VERSION}"
    echo "build=${BUILD_NUM}"
    echo "bundle=${BUNDLE}"
    echo "sha=${SHA}"
    echo "short_sha=${SHORT_SHA}"
  } >> "${GITHUB_OUTPUT}"
fi
