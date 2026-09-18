"""!
@file config_loader.py
@brief Utilidad compartida para cargar config.yaml expandiendo variables de entorno.

Los valores en config.yaml pueden contener referencias a variables de entorno
usando la sintaxis ${VARIABLE} (o $VARIABLE). Esta utilidad sustituye esas
referencias por sus valores reales en tiempo de carga

Uso:
    from shared_pkg.config_loader import load_config
    cfg = load_config()
    url = cfg['servicios']['moodle']['url_base'] 
"""
import os
import yaml


def _expand_env_vars(obj):
    """Expande recursivamente ${VAR} en todos los strings de un dict/list."""
    if isinstance(obj, dict):
        return {k: _expand_env_vars(v) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [_expand_env_vars(item) for item in obj]
    elif isinstance(obj, str):
        return os.path.expandvars(obj)
    else:
        return obj


def load_config(path: str | None = None) -> dict:
    """!
    @brief Lee config.yaml y expande automáticamente variables de entorno.

    @param path Ruta opcional al archivo. Si None, usa CONFIG_PATH o el default /config/config.yaml.
    @return Diccionario con la configuración completamente resuelto.
    """
    if path is None:
        path = os.getenv("CONFIG_PATH", "/config/config.yaml")

    # Fallback para ejecución local fuera de Docker
    if not os.path.exists(path):
        local_path = os.path.abspath(
            os.path.join(os.path.dirname(__file__), "../../../../config/config.yaml")
        )
        if os.path.exists(local_path):
            path = local_path

    with open(path, "r", encoding="utf-8") as f:
        raw = yaml.safe_load(f)

    return _expand_env_vars(raw) if raw else {}
