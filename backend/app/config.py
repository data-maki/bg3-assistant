from functools import lru_cache
from pathlib import Path
from typing import Literal
from urllib.parse import urlsplit
from dotenv import load_dotenv
from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

from .paths import backend_root, default_state_root

ROOT_DIR = backend_root()
# Dev checkout .env, repo-root .env, and — for the frozen app, whose backend
# lives read-only inside the bundle — the writable per-user state directory.
load_dotenv(ROOT_DIR / ".env")
load_dotenv(ROOT_DIR.parent / ".env")
load_dotenv(default_state_root() / ".env")


class Settings(BaseSettings):
    openrouter_api_key: str = Field(default="", alias="OPENROUTER_API_KEY")
    openrouter_model: str = Field(default="google/gemini-3-flash-preview", alias="OPENROUTER_MODEL")
    exa_api_key: str = Field(default="", alias="EXA_API_KEY")
    upstream_backend_url: str = Field(default="", alias="BG3_UPSTREAM_BACKEND_URL")
    backend_mode: Literal["local", "hosted"] = Field(default="local", alias="BG3_BACKEND_MODE")
    companion_control_token: str = Field(default="", alias="BG3_COMPANION_CONTROL_TOKEN")
    appstore_bundle_id: str = Field(default="com.datamaki.BG3HonorAssistant", alias="BG3_APPSTORE_BUNDLE_ID")
    appstore_apple_id: int | None = Field(default=None, alias="BG3_APPSTORE_APPLE_ID")
    appstore_environment: Literal["Sandbox", "Production"] = Field(
        default="Sandbox", alias="BG3_APPSTORE_ENVIRONMENT"
    )
    apple_root_ca_dir: Path = Field(default=ROOT_DIR / "certs", alias="BG3_APPLE_ROOT_CA_DIR")
    apple_online_checks: bool = Field(default=True, alias="BG3_APPLE_ONLINE_CHECKS")
    auth_token_secret: str = Field(default="", alias="BG3_AUTH_TOKEN_SECRET")
    subject_hmac_secret: str = Field(default="", alias="BG3_SUBJECT_HMAC_SECRET")
    auth_token_ttl_seconds: int = Field(default=3600, alias="BG3_AUTH_TOKEN_TTL_SECONDS")
    usage_database_path: Path = Field(
        default=default_state_root() / "usage.sqlite3", alias="BG3_USAGE_DB_PATH"
    )
    build_import_lifetime_limit: int = Field(default=30, alias="BG3_BUILD_IMPORT_LIFETIME_LIMIT")
    import_processing_lease_seconds: int = Field(
        default=600, alias="BG3_IMPORT_PROCESSING_LEASE_SECONDS"
    )
    runs_dir: Path = default_state_root()
    state_database_path: Path | None = Field(default=None, alias="BG3_STATE_DB_PATH")

    model_config = SettingsConfigDict(extra="ignore")

    @field_validator("upstream_backend_url")
    @classmethod
    def validate_upstream_backend_url(cls, value: str) -> str:
        value = value.strip().rstrip("/")
        if not value:
            return ""
        parsed = urlsplit(value)
        if (
            parsed.scheme != "https"
            or not parsed.hostname
            or parsed.username is not None
            or parsed.password is not None
            or parsed.path
            or parsed.query
            or parsed.fragment
            or parsed.hostname.lower() in {"localhost", "127.0.0.1", "::1"}
        ):
            raise ValueError("BG3_UPSTREAM_BACKEND_URL must be a remote HTTPS origin.")
        return value


@lru_cache
def get_settings() -> Settings:
    return Settings()
