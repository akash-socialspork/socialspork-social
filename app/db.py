from collections.abc import Iterator
from typing import Any

from sqlalchemy import create_engine, text
from sqlalchemy.engine import Connection

from app.config import get_settings

engine = create_engine(get_settings().database_url, pool_pre_ping=True)


def get_db() -> Iterator[Connection]:
    """FastAPI dependency: one transaction per request, committed on success."""
    with engine.begin() as conn:
        yield conn


def fetch_all(conn: Connection, sql: str, **params: Any) -> list[dict]:
    return [dict(r) for r in conn.execute(text(sql), params).mappings()]


def execute(conn: Connection, sql: str, **params: Any) -> int:
    return conn.execute(text(sql), params).rowcount


def fetch_one(conn: Connection, sql: str, **params: Any) -> dict | None:
    row = conn.execute(text(sql), params).mappings().first()
    return dict(row) if row else None
