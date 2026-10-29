from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

ENV_FILE = Path(__file__).resolve().parent.parent / ".env"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=ENV_FILE, extra="ignore")

    app_env: str = "local"
    database_url: str = "postgresql+psycopg://localhost:5432/socialspork"

    google_client_id: str = ""
    google_client_secret: str = ""
    google_api_key: str = ""

    zomato_base_url: str = ""
    zomato_api_key: str = ""

    swiggy_base_url: str = ""
    swiggy_api_key: str = ""

    anthropic_api_key: str = ""


@lru_cache
def get_settings() -> Settings:
    return Settings()
