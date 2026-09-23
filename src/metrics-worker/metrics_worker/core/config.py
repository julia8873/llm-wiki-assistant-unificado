from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    # Mapeo API — URL interna Docker y token de autenticación
    mapeo_api_url: str
    mapeo_api_token: str

    # Intervalos de trabajo (en segundos)
    poll_interval_sec: int = 15
    reconciliation_interval_sec: int = 86400

    # Control de comportamiento
    mock_services: bool = False
    max_concurrency: int = 2

    # Tokens de proveedores Git
    github_token: str = ""
    gitlab_token: str = ""
    git_self_hosted_token: str = ""

    # URLs base de las APIs Git
    github_api_base_url: str = "https://api.github.com"
    gitlab_api_base_url: str = "https://gitlab.com/api/v4"
    self_hosted_api_base_url: str = ""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore"
    )

settings = Settings()
