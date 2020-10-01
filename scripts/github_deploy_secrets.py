#!/usr/bin/env python3
from base64 import b64encode
from getpass import getpass
from io import StringIO
from nacl import encoding, public
from paramiko import RSAKey, ssh_exception
from requests.exceptions import HTTPError
from time import time

import jwt
import os
import requests
import sys

GITHUB_APP_CLIENT_ID = os.environ['GITHUB_APP_CLIENT_ID']
GITHUB_INSTALL_ID = os.environ['GITHUB_INSTALL_ID']
GITHUB_SECRETS_PK_PEM_FILE = os.environ['GITHUB_SECRETS_PK_PEM_FILE']
SSH_CERT_FILE = os.environ['SSH_CERT_FILE']
SSH_PRIV_KEY = os.environ['SSH_PRIV_KEY']


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
    return b64encode(encrypted).decode("utf-8")


def update_github_secret(token_headers: dict, github_pub_key_JSON: dict,
                         file_to_be_encoded: str, secret_name: str):
    secrets_url = 'https://api.github.com/orgs/ackersonde/actions/secrets'
    b64_encoded_value = encrypt(github_pub_key_JSON['key'],
                                open(file_to_be_encoded).read())
    r = requests.put(
        f'{secrets_url}/{secret_name}',
        json={"encrypted_value": f"{b64_encoded_value}",
              "key_id": f"{github_pub_key_JSON['key_id']}",
              "visibility": "all"},
        headers=token_headers)
    r.raise_for_status()
    # print(f'Updated {secret_name} with new encoded value of {file_to_be_encoded}')


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
    except HTTPError as http_err:
        fatal(f'HTTP error occurred: {http_err}')
    except Exception as err:
        fatal(f'Other error occurred: {err}')


if __name__ == '__main__':
    main()