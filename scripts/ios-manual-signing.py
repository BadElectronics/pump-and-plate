#!/usr/bin/env python3
"""Switches the app target (and only that target) to the cloud build's
App Store certificate and profile, so the packages it uses are left alone.

  ios-manual-signing.py ios/Runner.xcodeproj/project.pbxproj BUNDLE_ID TEAM PROFILE_NAME
"""
import re
import sys

pbx, bundle_id, team, profile = sys.argv[1:5]
text = open(pbx).read()

marker = f"PRODUCT_BUNDLE_IDENTIFIER = {bundle_id};"
settings = (
    f'CODE_SIGN_STYLE = Manual;\n'
    f'\t\t\t\tDEVELOPMENT_TEAM = {team};\n'
    f'\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = "{profile}";\n'
    f'\t\t\t\tCODE_SIGN_IDENTITY = "Apple Distribution";\n'
    f'\t\t\t\t"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "Apple Distribution";\n'
)


def fix(block):
    body = block.group(0)
    if marker not in body:
        return body
    # Drop any signing lines the template set, then add ours.
    body = re.sub(r'\n\t+(CODE_SIGN_STYLE|DEVELOPMENT_TEAM|PROVISIONING_PROFILE_SPECIFIER|"?CODE_SIGN_IDENTITY(\[sdk=iphoneos\*\])?"?) = [^;]*;', "", body)
    return body.replace("buildSettings = {\n", "buildSettings = {\n\t\t\t\t" + settings, 1)


new, n = re.subn(r"\{\s*isa = XCBuildConfiguration;.*?\n\t\t\};", fix, text, flags=re.S)
count = new.count('PROVISIONING_PROFILE_SPECIFIER = "')
if count == 0:
    sys.exit(f"Couldn't find the {bundle_id} target's settings in {pbx}")
open(pbx, "w").write(new)
print(f"Manual App Store signing set on {count} configurations of {bundle_id}.")
