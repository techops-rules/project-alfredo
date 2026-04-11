#!/usr/bin/env python3
"""
Send an APNs push notification from the Pi to the alfredo iOS app.

Usage:
    python3 apns-send.py "alfredo is ready"
    python3 apns-send.py --title "ALFREDO" --body "response complete"

Reads config from ~/alfredo-kiosk/apns-config.json and device token
from ~/alfredo-kiosk/device-token.txt.

Requires: pip install httpx PyJWT cryptography
"""

import argparse
import json
import os
import time
import sys

import httpx
import jwt

CONFIG_PATH = os.path.expanduser("~/alfredo-kiosk/apns-config.json")
TOKEN_PATH = os.path.expanduser("~/alfredo-kiosk/device-token.txt")


def load_config():
    if not os.path.exists(CONFIG_PATH):
        print(f"Error: config not found at {CONFIG_PATH}", file=sys.stderr)
        print("Create it with: key_path, key_id, team_id, bundle_id", file=sys.stderr)
        sys.exit(1)
    with open(CONFIG_PATH) as f:
        return json.load(f)


def load_device_token():
    if not os.path.exists(TOKEN_PATH):
        print(f"Error: device token not found at {TOKEN_PATH}", file=sys.stderr)
        print("Open the alfredo app on your iPhone to register.", file=sys.stderr)
        sys.exit(1)
    with open(TOKEN_PATH) as f:
        return f.read().strip()


def make_apns_jwt(key_path, key_id, team_id):
    with open(key_path) as f:
        private_key = f.read()
    payload = {
        "iss": team_id,
        "iat": int(time.time()),
    }
    headers = {
        "alg": "ES256",
        "kid": key_id,
    }
    return jwt.encode(payload, private_key, algorithm="ES256", headers=headers)


def send_notification(title, body, config, device_token):
    token = make_apns_jwt(config["key_path"], config["key_id"], config["team_id"])
    bundle_id = config.get("bundle_id", "com.todd.alfredo")

    # Use sandbox for development, production for release
    use_sandbox = config.get("sandbox", True)
    if use_sandbox:
        apns_url = f"https://api.sandbox.push.apple.com/3/device/{device_token}"
    else:
        apns_url = f"https://api.push.apple.com/3/device/{device_token}"

    payload = {
        "aps": {
            "alert": {
                "title": title,
                "body": body,
            },
            "sound": "default",
        },
    }

    headers = {
        "authorization": f"bearer {token}",
        "apns-topic": bundle_id,
        "apns-push-type": "alert",
        "apns-priority": "10",
    }

    with httpx.Client(http2=True) as client:
        response = client.post(apns_url, json=payload, headers=headers)

    if response.status_code == 200:
        print("Push sent successfully")
    else:
        print(f"APNs error {response.status_code}: {response.text}", file=sys.stderr)
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description="Send APNs push to alfredo app")
    parser.add_argument("message", nargs="?", default="alfredo is ready")
    parser.add_argument("--title", default="ALFREDO")
    parser.add_argument("--body", default=None)
    args = parser.parse_args()

    body = args.body or args.message
    config = load_config()
    device_token = load_device_token()

    send_notification(args.title, body, config, device_token)


if __name__ == "__main__":
    main()
