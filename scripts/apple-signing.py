#!/usr/bin/env python3
"""Makes a short-lived App Store signing certificate and profile for the cloud
build, and removes them afterwards. Nothing secret is kept between builds.

Apple re-signs every build it accepts, so revoking the certificate after the
upload doesn't affect builds already on TestFlight or the App Store.

Needs the App Store Connect API key in the environment:
  APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_KEY_PATH

  apple-signing.py setup BUNDLE_ID OUT_DIR P12_PASSWORD
      Writes OUT_DIR/dist.p12 and OUT_DIR/profile.mobileprovision and prints
      key=value lines: team, cert_id, profile_id, profile_name, profile_uuid.
  apple-signing.py cleanup CERT_ID PROFILE_ID
"""
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt  # PyJWT
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

API = "https://api.appstoreconnect.apple.com/v1"


def token():
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
        sys.exit(f"App Store Connect said {e.code} to {method} {path}: {e.read().decode()[:800]}")


def bundle(bundle_id):
    q = urllib.parse.urlencode({"filter[identifier]": bundle_id, "fields[bundleIds]": "identifier,seedId"})
    for item in call("GET", f"/bundleIds?{q}").get("data", []):
        if item["attributes"].get("identifier") == bundle_id:
            return item["id"], item["attributes"]["seedId"]
    sys.exit(f"No App ID {bundle_id}. Register it at developer.apple.com → Identifiers.")


def setup(bundle_id, out_dir, p12_password):
    bundle_res, team = bundle(bundle_id)

    # A new key and certificate request, made here and never stored.
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    csr = (x509.CertificateSigningRequestBuilder()
           .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Pump and Plate cloud build")]))
           .sign(key, hashes.SHA256()))
    cert = call("POST", "/certificates", {"data": {"type": "certificates", "attributes": {
        "certificateType": "DISTRIBUTION",
        "csrContent": csr.public_bytes(serialization.Encoding.PEM).decode(),
    }}})["data"]
    cert_id = cert["id"]
    der = base64.b64decode(cert["attributes"]["certificateContent"])
    certificate = x509.load_der_x509_certificate(der)

    name = f"Pump and Plate cloud build {time.strftime('%Y%m%d-%H%M%S')}"
    profile = call("POST", "/profiles", {"data": {
        "type": "profiles",
        "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bundle_res}},
            "certificates": {"data": [{"type": "certificates", "id": cert_id}]},
        },
    }})["data"]

    os.makedirs(out_dir, exist_ok=True)
    # The older p12 encryption, which macOS's keychain tool can read.
    enc = (serialization.PrivateFormat.PKCS12.encryption_builder()
           .kdf_rounds(2048)
           .key_cert_algorithm(pkcs12.PBES.PBESv1SHA1And3KeyTripleDESCBC)
           .hmac_hash(hashes.SHA1())
           .build(p12_password.encode()))
    with open(os.path.join(out_dir, "dist.p12"), "wb") as f:
        f.write(pkcs12.serialize_key_and_certificates(b"Pump and Plate", key, certificate, None, enc))
    with open(os.path.join(out_dir, "profile.mobileprovision"), "wb") as f:
        f.write(base64.b64decode(profile["attributes"]["profileContent"]))

    print(f"team={team}")
    print(f"cert_id={cert_id}")
    print(f"profile_id={profile['id']}")
    print(f"profile_name={name}")
    print(f"profile_uuid={profile['attributes']['uuid']}")


def cleanup(cert_id, profile_id):
    for path in (f"/profiles/{profile_id}", f"/certificates/{cert_id}"):
        if path.endswith("/"):
            continue
        req = urllib.request.Request(API + path, method="DELETE", headers={"Authorization": f"Bearer {token()}"})
        try:
            urllib.request.urlopen(req, timeout=60)
            print(f"Removed {path}")
        except urllib.error.HTTPError as e:
            print(f"Couldn't remove {path}: {e.code}")


if __name__ == "__main__":
    if len(sys.argv) == 5 and sys.argv[1] == "setup":
        setup(sys.argv[2], sys.argv[3], sys.argv[4])
    elif len(sys.argv) == 4 and sys.argv[1] == "cleanup":
        cleanup(sys.argv[2], sys.argv[3])
    else:
        sys.exit(__doc__)
