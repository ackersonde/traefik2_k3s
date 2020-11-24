#!/usr/bin/env python3
from getpass import getpass
from io import StringIO
from nacl import encoding, public
from paramiko import RSAKey, ssh_exception
from pathlib import Path
from requests.exceptions import HTTPError
from time import time

import base64
import jwt
import os
import requests
import sys

GITHUB_APP_CLIENT_ID = os.environ['GITHUB_APP_CLIENT_ID']
GITHUB_INSTALL_ID = os.environ['GITHUB_INSTALL_ID']
GITHUB_SECRETS_PK_PEM_FILE = os.environ['GITHUB_SECRETS_PK_PEM_FILE']
SSH_CERT_FILE = os.environ['SSH_CERT_FILE']
SSH_PRIV_KEY = os.environ['SSH_PRIV_KEY']
WG_PEER_CONFIG_FILE = os.environ['WG_PEER_CONFIG_FILE']


def fatal(message):
    print('Error: {}'.format(message), file=sys.stderr)
    sys.exit(1)


# Token Exchange requires a JWT in the Auth Bearer header with this format
def generate_id_token(iss, private_key, expire_seconds=600):
    new_jwt = jwt.encode(
        {'iss': iss, 'iat': int(time()), 'exp': int(time()) + expire_seconds},
        private_key, algorithm='RS256')
    # python3 jwt returns bytes, so we need to decode to string
    return new_jwt.decode()


# Load the private key from a file and decrypt if necessary
def get_private_key(file_name, password=None):
    try:
        rsa_key = RSAKey.from_private_key_file(
            GITHUB_SECRETS_PK_PEM_FILE, password)
    except ssh_exception.PasswordRequiredException:
        password = getpass(prompt="Private key password: ")
        return get_private_key(file_name, password)
    except ssh_exception.SSHException:
        fatal('Invalid private key password')
    except FileNotFoundError:
        fatal('Could not find private key file')
    with StringIO() as buf:
        rsa_key.write_private_key(buf)
        return buf.getvalue()


def encrypt(public_key: str, secret_value: str) -> str:
    """Encrypt a Unicode string using the public key."""
    public_key = public.PublicKey(
        public_key.encode("utf-8"), encoding.Base64Encoder())
    sealed_box = public.SealedBox(public_key)
    encrypted = sealed_box.encrypt(secret_value.encode("utf-8"))
    return base64.b64encode(encrypted).decode("utf-8")


def update_github_secret(
        token_headers: dict, github_pub_key_JSON: dict,
        file_to_be_encoded: str, secret_name: str, b64encode=True):
    msg = ""
    if b64encode:
        base64_bytes = base64.b64encode(Path(file_to_be_encoded).read_bytes())
        msg = base64_bytes.decode("utf-8")
    else:
        msg = Path(file_to_be_encoded).read_text()

    secrets_url = 'https://api.github.com/orgs/ackersonde/actions/secrets'
    encrypted_value = encrypt(github_pub_key_JSON['key'], msg)
    r = requests.put(
        f'{secrets_url}/{secret_name}',
        json={"encrypted_value": f"{encrypted_value}",
              "key_id": f"{github_pub_key_JSON['key_id']}",
              "visibility": "all"},
        headers=token_headers)
    r.raise_for_status()


def redeploy_bender_slackbot(access_token: str):
    token_headers = {'Accept': 'application/vnd.github.v3+json',
                     'Authorization': f'token {access_token}'}

    resp = requests.post(
        'https://api.github.com/repos/ackersonde/bender-slackbot/actions/workflows/build.yml/dispatches',
        json={"ref": "master"},
        headers=token_headers)
    resp.raise_for_status()


def main():
    # Generate a new JWT using id and private key
    pri_key = get_private_key(GITHUB_SECRETS_PK_PEM_FILE)
    id_token = generate_id_token(GITHUB_APP_CLIENT_ID, pri_key)

    # https://docs.github.com/en/free-pro-team@latest/rest/reference/actions#secrets
    try:
        url = f'https://api.github.com/app/installations/{GITHUB_INSTALL_ID}/access_tokens'
        auth_headers = {'Accept': 'application/vnd.github.v3+json',
                        'Authorization': f'Bearer {id_token}'}
        resp = requests.post(url, headers=auth_headers)
        resp.raise_for_status()
        output = resp.json()
        access_token = output['token']

        url = 'https://api.github.com/orgs/ackersonde/actions/secrets/public-key'
        token_headers = {'Accept': 'application/vnd.github.v3+json',
                         'Authorization': f'token {access_token}'}
        resp = requests.get(url, headers=token_headers)
        resp.raise_for_status()
        github_pub_key_JSON = resp.json()

        update_github_secret(token_headers, github_pub_key_JSON, SSH_PRIV_KEY,
                             "CTX_SERVER_DEPLOY_SECRET_B64")
        update_github_secret(token_headers, github_pub_key_JSON, SSH_CERT_FILE,
                             "CTX_SERVER_DEPLOY_CACERT_B64")
        update_github_secret(token_headers, github_pub_key_JSON,
                             WG_PEER_CONFIG_FILE,
                             "CTX_WIREGUARD_GITHUB_ACTIONS_CLIENT_CONFIG",
                             b64encode=False)

        redeploy_bender_slackbot(access_token)
    except HTTPError as http_err:
        fatal(f'HTTP error occurred: {http_err}')
    except Exception as err:
        fatal(f'Other error occurred: {err}')


if __name__ == '__main__':
    main()
