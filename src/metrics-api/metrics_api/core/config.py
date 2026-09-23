from pydantic_settings import BaseSettings, SettingsConfigDict
from typing import Optional

class Settings(BaseSettings):
    environment: str = "dev"

    # URLs de servicios internos Docker
    frontend_url: str
    moodle_auth_url: str
    moodle_host_header: str
    mapeo_api_url: str

    # Autenticación
    mapeo_api_token: str
    jwt_secret_key: str
    jwt_algorithm: str = "HS256"

    # GitHub tokens
    github_token_agent: str = ""
    github_token: str = ""

    # Feature flags
    enable_evaluation_agent: bool = False

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore"
    )

settings = Settings()
