from functools import lru_cache
from pathlib import Path
from dotenv import load_dotenv
from pydantic import Field
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
    runs_dir: Path = default_state_root()
    state_database_path: Path | None = Field(default=None, alias="BG3_STATE_DB_PATH")

    model_config = SettingsConfigDict(extra="ignore")


@lru_cache
def get_settings() -> Settings:
    return Settings()
