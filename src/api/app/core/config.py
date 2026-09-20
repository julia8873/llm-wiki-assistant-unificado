from pydantic import ConfigDict
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """
    Configuración central de la API.
    Lee las variables del .env y usa pydantic para comprobar que las variables 
    necesarias para que el proyecto funcione se encuentren definidas y tengan el 
    tipo de dato correcto.
    """

    # Variables que buscarán en el archivo .env:
    DATABASE_URL: str
    MAPEO_API_TOKEN: str
    ENVIRONMENT: str = "local"
    PUBLIC_API_URL: str | None = None
    GITHUB_WEBHOOK_SECRET: str | None = None
    
    GITHUB_PAT: str | None = None
    GITLAB_TOKEN: str | None = None
    GIT_SELF_HOSTED_TOKEN: str | None = None

    model_config = ConfigDict(env_file=".env", extra="ignore")


settings = Settings()
