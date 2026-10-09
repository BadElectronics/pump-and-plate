"""Checks the Google Play upload robot can reach Pump and Plate.

Read-only: it opens a draft edit, reads the Production track and the tip
products, then deletes the draft without committing, so nothing on Google
Play changes. Run by the cloud build with PLAY_SERVICE_ACCOUNT_JSON set.
"""
import json
import os
import sys

import requests
from google.auth.transport.requests import Request
from google.oauth2 import service_account

PKG = 'com.pumpandplate.app'
BASE = f'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PKG}'


def say(level, title, text):
    print(f'::{level} title={title}::{text}'.replace('\n', ' '))


raw = os.environ.get('PLAY_JSON', '')
if not raw:
    say('warning', 'Google Play access', 'No PLAY_SERVICE_ACCOUNT_JSON secret, so the check was skipped.')
    sys.exit(0)
try:
    key = json.loads(raw)
except ValueError:
    say('error', 'Google Play access', 'The PLAY_SERVICE_ACCOUNT_JSON secret is not valid JSON. Paste the whole key file again.')
    sys.exit(1)

creds = service_account.Credentials.from_service_account_info(
    key, scopes=['https://www.googleapis.com/auth/androidpublisher'])
creds.refresh(Request())
h = {'Authorization': f'Bearer {creds.token}'}
robot = key.get('client_email', 'the robot')

r = requests.post(f'{BASE}/edits', headers=h, json={}, timeout=30)
if r.status_code != 200:
    msg = r.json().get('error', {}).get('message', r.text[:200]) if r.headers.get('content-type', '').startswith('application/json') else r.text[:200]
    say('error', 'Google Play access', f'{robot} could not open Pump and Plate (HTTP {r.status_code}): {msg}. '
        'If you invited it in Play Console in the last day, Google can take up to 24 hours to switch the access on.')
    sys.exit(1)
edit = r.json()['id']
try:
    t = requests.get(f'{BASE}/edits/{edit}/tracks/production', headers=h, timeout=30)
    releases = t.json().get('releases', []) if t.status_code == 200 else []
    prod = ', '.join(f"{x.get('name', '?')} ({x.get('status', '?')}, version code {','.join(x.get('versionCodes', []))})" for x in releases) or 'no releases yet'
    say('notice', 'Google Play access', f'The upload robot can reach Pump and Plate. Production track: {prod}.')
finally:
    requests.delete(f'{BASE}/edits/{edit}', headers=h, timeout=30)   # never committed, so nothing changes

p = requests.get(f'{BASE}/onetimeproducts', headers=h, params={'pageSize': 100}, timeout=30)
if p.status_code == 200:
    ids = sorted((x.get('productId', '') for x in p.json().get('oneTimeProducts', [])), key=lambda s: int(s.split('_')[-1]) if s.split('_')[-1].isdigit() else 0)
    say('notice', 'Tip products', f'{len(ids)} found: {", ".join(ids) or "none"}.')
else:
    say('notice', 'Tip products', f'Could not list them (HTTP {p.status_code}); the robot may not have permission to view products, which is fine for uploading.')
