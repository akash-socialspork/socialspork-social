import json
import os

from dotenv import dotenv_values

from app.config import ENV_FILE
from app.connectors.base import Connector
from app.connectors.google import GoogleConnector
from app.connectors.swiggy import SwiggyConnector
from app.connectors.zomato import ZomatoConnector

_REGISTRY: dict[str, type[Connector]] = {
    c.platform_code: c for c in (GoogleConnector, ZomatoConnector, SwiggyConnector)
}


def resolve_credentials(credentials_ref: str | None) -> dict:
    """platform_connections.credentials_ref -> credentials dict.

    Local dev: "env:VAR_NAME" reads a JSON object from that env var.
    Replace with a secrets manager before production.
    """
    if not credentials_ref:
        return {}
    if credentials_ref.startswith("env:"):
        name = credentials_ref[4:]
        value = os.environ.get(name) or dotenv_values(ENV_FILE).get(name) or "{}"
        return json.loads(value)
    raise ValueError(f"Unsupported credentials_ref: {credentials_ref}")


def get_connector(platform_code: str, credentials_ref: str | None = None) -> Connector:
    cls = _REGISTRY.get(platform_code)
    if not cls:
        raise NotImplementedError(f"No connector for platform '{platform_code}'")
    return cls(resolve_credentials(credentials_ref))
