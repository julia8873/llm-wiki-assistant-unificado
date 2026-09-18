import os
from shared_pkg.config_loader import load_config
from .base import GitProviderClient

class GitProviderConfigError(Exception):
    pass

def load_config_git():
    """!
    @brief Carga la configuración desde config.yaml con expansión de variables de entorno.
    @return dict|None Retorna la configuración como diccionario o None si falla.
    """
    try:
        return load_config()
    except Exception:
        return None

def get_git_provider() -> GitProviderClient:
    """!
    @brief Factoría para obtener el cliente del proveedor Git configurado.
    @return Instancia de GitProviderClient concreta.
    """
    config = load_config_git()
    if not config or 'git' not in config:
        raise GitProviderConfigError("Configuración 'git' no encontrada en config.yaml")

    proveedor = config['git'].get('proveedor_activo', 'github')

    if proveedor == 'github':
        from .github_provider import GitHubProvider
        return GitHubProvider(config)
    elif proveedor == 'gitlab':
        from .gitlab_provider import GitLabProvider
        return GitLabProvider(config)
    elif proveedor == 'self_hosted':
        from .self_hosted_provider import SelfHostedProvider
        return SelfHostedProvider(config)
    else:
        raise GitProviderConfigError(f"Proveedor Git no soportado: {proveedor}")
