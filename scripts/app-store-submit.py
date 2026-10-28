#!/usr/bin/env python3
"""Sends a release to App Store review, after the iPhone build has gone to
TestFlight. Waits for Apple to finish processing the build, creates the App
Store version (or reuses it), fills in What's New, attaches the build and
submits it. Screenshots, description and the rest carry over from the
previous version, as they do when this is done by hand.

Needs the App Store Connect API key in the environment:
  APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_KEY_PATH

  app-store-submit.py BUNDLE_ID VERSION BUILD_NUMBER WHATS_NEW_FILE
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"
WAIT_SECONDS = 75 * 60  # Apple usually processes a build in 5 to 30 minutes.
POLL_SECONDS = 60


def token():
    import jwt  # PyJWT

    key = open(os.environ["APP_STORE_CONNECT_KEY_PATH"]).read()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"], "iat": now, "exp": now + 900,
         "aud": "appstoreconnect-v1"},
        key, algorithm="ES256",
        headers={"kid": os.environ["APP_STORE_CONNECT_KEY_ID"], "typ": "JWT"},
    )


def call(method, path, body=None):
    req = urllib.request.Request(
        API + path, method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        sys.exit(f"App Store Connect said {e.code} to {method} {path}: {e.read().decode()[:1500]}")


def q(**params):
    return "?" + urllib.parse.urlencode(params)


def app_id(bundle_id):
    data = call("GET", "/apps" + q(**{"filter[bundleId]": bundle_id}))["data"]
    if not data:
        sys.exit(f"No app with bundle ID {bundle_id} in App Store Connect.")
    return data[0]["id"]


def wait_for_build(app, version, build_number, sleep=time.sleep, clock=time.monotonic):
    """The build's id once Apple has finished processing it."""
    deadline = clock() + WAIT_SECONDS
    while True:
        found = call("GET", "/builds" + q(**{
            "filter[app]": app,
            "filter[version]": str(build_number),
            "filter[preReleaseVersion.version]": version,
        }))["data"]
        if found:
            state = found[0]["attributes"].get("processingState")
            if state == "VALID":
                print(f"Build {version} ({build_number}) is processed.")
                return found[0]["id"]
            if state in ("FAILED", "INVALID"):
                sys.exit(f"Apple couldn't process build {version} ({build_number}): {state}. Check the email from App Store Connect.")
            print(f"Build {version} ({build_number}) is {state}; waiting.")
        else:
            print(f"Build {version} ({build_number}) hasn't shown up yet; waiting.")
        if clock() > deadline:
            sys.exit(f"Build {version} ({build_number}) still wasn't ready after {WAIT_SECONDS // 60} minutes. "
                     "Submit it by hand in App Store Connect once it shows as ready.")
        sleep(POLL_SECONDS)


def store_version(app, version):
    """The App Store version for [version], made if it doesn't exist yet."""
    found = call("GET", f"/apps/{app}/appStoreVersions" + q(**{
        "filter[versionString]": version, "filter[platform]": "IOS"}))["data"]
    if found:
        state = found[0]["attributes"].get("appStoreState") or found[0]["attributes"].get("appVersionState")
        print(f"Version {version} already exists ({state}); using it.")
        return found[0]["id"]
    made = call("POST", "/appStoreVersions", {"data": {
        "type": "appStoreVersions",
        "attributes": {"platform": "IOS", "versionString": version, "releaseType": "AFTER_APPROVAL"},
        "relationships": {"app": {"data": {"type": "apps", "id": app}}},
    }})["data"]
    print(f"Made App Store version {version}.")
    return made["id"]


def set_whats_new(version_id, text):
    locs = call("GET", f"/appStoreVersions/{version_id}/appStoreVersionLocalizations")["data"]
    if not locs:
        sys.exit("The new version has no localizations to put What's New in.")
    for loc in locs:
        call("PATCH", f"/appStoreVersionLocalizations/{loc['id']}", {"data": {
            "type": "appStoreVersionLocalizations", "id": loc["id"],
            "attributes": {"whatsNew": text},
        }})
        print(f"What's New set for {loc['attributes'].get('locale')}.")


def attach_build(version_id, build_id):
    call("PATCH", f"/appStoreVersions/{version_id}/relationships/build",
         {"data": {"type": "builds", "id": build_id}})
    print("Build attached.")


def submit(app, version_id):
    drafts = call("GET", "/reviewSubmissions" + q(**{
        "filter[app]": app, "filter[platform]": "IOS", "filter[state]": "READY_FOR_REVIEW"}))["data"]
    if drafts:
        sub = drafts[0]["id"]
        print("Using the existing draft submission.")
    else:
        sub = call("POST", "/reviewSubmissions", {"data": {
            "type": "reviewSubmissions",
            "attributes": {"platform": "IOS"},
            "relationships": {"app": {"data": {"type": "apps", "id": app}}},
        }})["data"]["id"]
    items = call("GET", f"/reviewSubmissions/{sub}/items")["data"]
    has_version = any(
        (i.get("relationships", {}).get("appStoreVersion", {}).get("data") or {}).get("id") == version_id
        for i in items)
    if not has_version:
        call("POST", "/reviewSubmissionItems", {"data": {
            "type": "reviewSubmissionItems",
            "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub}},
                "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}},
            },
        }})
    call("PATCH", f"/reviewSubmissions/{sub}", {"data": {
        "type": "reviewSubmissions", "id": sub, "attributes": {"submitted": True}}})
    print("Submitted for App Review. Apple emails as it moves; it goes live on approval.")


def main(bundle_id, version, build_number, whats_new_file):
    text = open(whats_new_file, encoding="utf-8").read().strip()
    if not text:
        sys.exit(f"{whats_new_file} is empty.")
    app = app_id(bundle_id)
    build = wait_for_build(app, version, build_number)
    vid = store_version(app, version)
    set_whats_new(vid, text)
    attach_build(vid, build)
    submit(app, vid)


if __name__ == "__main__":
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    main(*sys.argv[1:])
