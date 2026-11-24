# Unsigned Fluxer IPA

Unofficial builder for a **sideloadable iOS app** of [Fluxer](https://fluxer.com), the open-source Discord alternative.

This repository does not contain Fluxer's source. The GitHub Action checks out the official client, [fluxerapp/flutter_client](https://github.com/fluxerapp/flutter_client) (AGPLv3), and produces an **unsigned** `.ipa`. Fluxer Platform AB does not publish this file and does not sign it.

An unsigned IPA will not open if you tap it in Safari or Files. You sign it with your own Apple ID, or you install it with TrollStore.

## Why this exists

As of 21 November 2026, from [Fluxer's own help page](https://fluxer.com/help/fluxer-app-store):

| Channel | Status |
| --- | --- |
| App Store | Version **2026.11.300** was submitted on 19 November 2026 and is waiting on Apple. Expected late November or early December 2026. |
| TestFlight | Paused. Apple-side bug. The public join link does not hand out installs. |
| AltStore PAL | Listed as "soon" in the official README. A source file is already in the client repo. |
| Android | On Google Play, and as FCM / OSS APKs on the official GitHub releases. |
| Web | [fluxer.com/app](https://fluxer.com/app) works in Safari today. |

The iOS and Android apps are the Flutter client in `fluxerapp/flutter_client` (default branch `canary`). Official iOS CI uses **Flutter 3.50.0** and **Xcode 27**, flavors `canary` / `beta` / `stable`, and `PUSH_PROVIDER=apns`. This Action follows that, then skips Apple's certificate.

- `beta` and `stable` use bundle id `com.fluxer`
- `canary` uses bundle id `com.fluxer.canary` (can sit next to the future App Store app)

Anything named Fluxer already on the App Store from another seller is not this app. Fluxer says so on that same help page.

## Get the IPA

1. Open the [Actions tab](https://github.com/testinganything/fluxer-ios-sideload/actions/workflows/unsigned-ipa.yml).
2. Run **Unsigned sideloadable IPA**.
3. Leave the defaults (`beta`, extensions removed, publish a Release) unless you want `canary` or `stable`.
4. When it finishes, download the `.ipa` from the [Releases](https://github.com/testinganything/fluxer-ios-sideload/releases) page. The matching upstream commit is in the release notes and in `BUILD_INFO.txt`.

The first run starts on its own when this workflow changes. A full build is a macOS job (Flutter, Rust native code, CocoaPods) and often takes 30 to 90 minutes.

`Runner.entitlements` is attached for people with a **paid** Apple Developer account who want to re-sign push, app groups, and associated domains themselves. The default IPA does not use those entitlements.

## Install on an iPhone

### Sideloadly (Windows or macOS, free Apple ID)

1. Install [Sideloadly](https://sideloadly.io).
2. Connect the iPhone and trust the computer.
3. Drop the `.ipa` in. Sign in with an Apple ID. An app-specific password is what Apple usually wants, not your normal password.
4. Install. If it complains about plugins or a bundle id that is already on the phone, remove the existing Fluxer beta or change the bundle id (for example `com.fluxer.sideload`).
5. On the phone: **Settings → General → VPN & Device Management → Trust**.

A free Apple ID install expires after **7 days**. Plug the phone back in and refresh it. You can only have a few sideloaded apps at once.

### SideStore or AltStore

Import the IPA into SideStore or AltStore the same way you import any other IPA. Refresh on the same Wi-Fi as the pairing computer before the 7 days are up. This is a normal sideload. It is not Fluxer's upcoming AltStore PAL listing, which has to be notarized by Fluxer.

### TrollStore

On iOS versions TrollStore still supports, you can install this unsigned IPA directly and it does not expire. That does not work on current iOS.

## What works, and what does not

The default build deletes the share extension, the notification-service extension, and the ReplayKit broadcast extension, and it is signed with none of Fluxer's special entitlements. That is what lets a free Apple ID install it.

| | Default unsigned IPA | App Store / paid re-sign |
| --- | --- | --- |
| Text chat, servers, DMs | Yes | Yes |
| Sign in to fluxer.com or your own instance | Yes | Yes |
| Voice and video | Should work (microphone permission) | Yes |
| Push notifications | No | Yes |
| Share sheet | No | Yes |
| Screen sharing from the phone | No | Yes |
| Universal links, passkeys, App Attest | No | Yes |

To build with the extensions left in, run the Action and turn **strip extensions** off. Installing that IPA needs a provisioning profile that covers every extension. A free Apple ID usually cannot.

## Build it yourself

The workflow is [`.github/workflows/unsigned-ipa.yml`](.github/workflows/unsigned-ipa.yml). It is the same shape as Fluxer's own iOS workflows, minus the certificate:

- runner `xcode-27` (Xcode 27.1 if the image has it)
- Flutter **3.50.0**
- `dart tool/configure_build.dart --profile=ios-store`
- Rust `aarch64-apple-ios`, plus the toolchain pinned for the native markdown crate
- `dart run build_runner build`
- `flutter build ios --release --no-codesign --flavor <flavor> --dart-define-from-file=tool/dart_defines/<flavor>.json --dart-define=PUSH_PROVIDER=apns`
- zip `Payload/<App>.app` with symlinks preserved (`zip -y`)

Local equivalent, on a Mac with Xcode 27 and Flutter 3.50.0:

```bash
git clone --recurse-submodules -b beta https://github.com/fluxerapp/flutter_client.git
cd flutter_client
# copy scripts/disable_codesign.sh and scripts/package_unsigned_ipa.sh next to the checkout
dart tool/configure_build.dart --profile=ios-store
flutter config --enable-native-assets
flutter pub get
bash tool/prefetch_native_rust_toolchains.sh
dart run build_runner build --delete-conflicting-outputs
bash disable_codesign.sh
flutter build ios --release --no-codesign \
  --flavor beta \
  --dart-define-from-file=tool/dart_defines/beta.json \
  --dart-define=PUSH_PROVIDER=apns
STRIP_EXTENSIONS=true FLAVOR=beta bash package_unsigned_ipa.sh
```

## License

The scripts and workflow in this repository are MIT. See [LICENSE](LICENSE).

The Fluxer app they compile is **not** MIT. It is the GNU Affero General Public License v3, plus Fluxer's App Store additional permission, both in [fluxerapp/flutter_client](https://github.com/fluxerapp/flutter_client). Every release of this IPA points at the exact upstream commit, which is the corresponding source.

Do not treat a download from this repo as an official Fluxer binary.
