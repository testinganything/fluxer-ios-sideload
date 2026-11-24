#!/usr/bin/env bash
# Make the official Fluxer iOS project build without an Apple certificate.
# Run from the flutter_client checkout root.
set -euo pipefail

python3 - <<'PY'
from pathlib import Path

pbx = Path("ios/Runner.xcodeproj/project.pbxproj")
text = pbx.read_text()
original = text
text = text.replace("CODE_SIGN_STYLE = Automatic;", "CODE_SIGN_STYLE = Manual;")
text = text.replace("DEVELOPMENT_TEAM = 3G5837T29K;", 'DEVELOPMENT_TEAM = "";')
# Any other team id that upstream may pin later.
import re
text = re.sub(r"DEVELOPMENT_TEAM = (?!\"\";)[^;]+;", 'DEVELOPMENT_TEAM = "";', text)
if "CODE_SIGNING_ALLOWED" not in text:
    text = text.replace(
        "CODE_SIGN_STYLE = Manual;",
        "\n".join([
            "CODE_SIGN_STYLE = Manual;",
            "\t\t\t\tCODE_SIGNING_ALLOWED = NO;",
            "\t\t\t\tCODE_SIGNING_REQUIRED = NO;",
            '\t\t\t\tCODE_SIGN_IDENTITY = "";',
            '\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = "";',
        ]),
    )
if text == original:
    raise SystemExit("project.pbxproj had no signing settings to patch")
pbx.write_text(text)
print(f"patched {pbx}")

podfile = Path("ios/Podfile")
pod = podfile.read_text()
needle = "config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'"
insert = needle + """
      config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
      config.build_settings['CODE_SIGNING_REQUIRED'] = 'NO'
      config.build_settings['CODE_SIGN_IDENTITY'] = ''
      config.build_settings['EXPANDED_CODE_SIGN_IDENTITY'] = ''
"""
if needle not in pod:
    raise SystemExit("Podfile post_install hook not found; upstream layout changed")
if "CODE_SIGNING_ALLOWED" not in pod:
    pod = pod.replace(needle, insert, 1)
    podfile.write_text(pod)
    print("patched ios/Podfile")

snippet = """
// Injected by fluxer-ios-sideload: compile without an Apple team.
CODE_SIGNING_ALLOWED=NO
CODE_SIGNING_REQUIRED=NO
CODE_SIGN_IDENTITY=
DEVELOPMENT_TEAM=
PROVISIONING_PROFILE_SPECIFIER=
CODE_SIGN_STYLE=Manual
"""
for rel in (
    "ios/Flutter/Release.xcconfig",
    "ios/Flutter/Debug.xcconfig",
    "ios/Flutter/Profile.xcconfig",
    "ios/Flutter/Extension.xcconfig",
):
    path = Path(rel)
    body = path.read_text() if path.exists() else ""
    if "CODE_SIGNING_ALLOWED=NO" not in body:
        path.write_text(body.rstrip() + "\n" + snippet)
        print(f"patched {rel}")
PY
