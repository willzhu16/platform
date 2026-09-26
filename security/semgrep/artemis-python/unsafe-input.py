"""Test fixture for unsafe-input.yaml - run with `semgrep --test`, gated by selftest.

Deliberately vulnerable scanner test data: never execute or copy into a project.
`ruleid:` = a finding is expected on the next line; `ok:` = none is.
"""

import pickle
import yaml

import httpx
import requests

path = "config.yaml"
blob = b""
url = "https://example.invalid/api"

# --- artemis-py-yaml-unsafe-load -------------------------------------------------------

# ruleid: artemis-py-yaml-unsafe-load
yaml.load(open(path))
# ruleid: artemis-py-yaml-unsafe-load
yaml.load(open(path), Loader=yaml.FullLoader)
# ruleid: artemis-py-yaml-unsafe-load
yaml.load(open(path), Loader=yaml.UnsafeLoader)
# ruleid: artemis-py-yaml-unsafe-load
yaml.unsafe_load(open(path))

# safe_load is the drop-in replacement, and the explicit SafeLoader is equivalent.
# ok: artemis-py-yaml-unsafe-load
yaml.safe_load(open(path))
# ok: artemis-py-yaml-unsafe-load
yaml.load(open(path), Loader=yaml.SafeLoader)
# ok: artemis-py-yaml-unsafe-load
yaml.dump({"a": 1})

# --- artemis-py-pickle-load ------------------------------------------------------------

# ruleid: artemis-py-pickle-load
pickle.load(open("state.bin", "rb"))
# ruleid: artemis-py-pickle-load
pickle.loads(blob)

# Writing a pickle is not the dangerous direction; reading one is.
# ok: artemis-py-pickle-load
pickle.dumps({"a": 1})

# --- artemis-py-tls-verify-disabled ----------------------------------------------------

# ruleid: artemis-py-tls-verify-disabled
requests.get(url, verify=False)
# ruleid: artemis-py-tls-verify-disabled
requests.post(url, json={}, verify=False)
# ruleid: artemis-py-tls-verify-disabled
httpx.get(url, verify=False)

# Validation left on, which is the default and needs no argument at all.
# ok: artemis-py-tls-verify-disabled
requests.get(url)
# ok: artemis-py-tls-verify-disabled
requests.get(url, verify=True)
# A CA bundle path is the correct way to trust a private authority.
# ok: artemis-py-tls-verify-disabled
requests.get(url, verify="/etc/ssl/certs/internal-ca.pem")


def fetch_with_session() -> None:
    """A session is how any CLI making more than one request is written."""
    session = requests.Session()
    # ruleid: artemis-py-tls-verify-disabled
    session.get(url, verify=False)


def fetch_with_session_ok() -> None:
    """Same shape, validation intact."""
    session = requests.Session()
    # ok: artemis-py-tls-verify-disabled
    session.get(url, timeout=5)
