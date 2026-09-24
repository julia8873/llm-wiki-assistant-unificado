"""! @file git_utils.py
@brief Utilidades compartidas para operaciones de Git.
"""

import os
import asyncio
import logging
from typing import Optional, Tuple
import redis.asyncio as redis
from contextlib import asynccontextmanager

logger = logging.getLogger(__name__)

redis_host = os.environ.get('REDIS_INTERNAL_HOSTNAME', 'redis')
redis_port = int(os.environ.get('REDIS_PORT', 6379))
redis_client = redis.Redis(host=redis_host, port=redis_port, decode_responses=True)

class LockAcquisitionError(Exception):
    pass

@asynccontextmanager
async def distributed_repo_lock(destino_local: str):
    """!
    @brief Adquiere un cerrojo distribuido en Redis para el repositorio local.
    @details
    Utiliza un cliente asíncrono de Redis para evitar bloquear el event loop.
    Incluye un TTL base de 60s (calibrado en base a ~1.6s medidos para clonado remoto)
    y un mecanismo de renovación periódica (heartbeat) para evitar expiraciones en operaciones lentas.
    Si el lock está ocupado, levanta LockAcquisitionError (aprovechado para reintentos en RQ).
    """
    lock_key = f"repo_lock:{destino_local}"
    ttl = 60
    lock = redis_client.lock(lock_key, timeout=ttl, blocking_timeout=30)
    
    acquired = await lock.acquire()
    if not acquired:
        raise LockAcquisitionError(f"El repositorio {destino_local} está bloqueado por otro proceso.")
    
    async def extend_lock_loop():
        try:
            while True:
                await asyncio.sleep(ttl / 3.0)
                try:
                    await lock.extend(ttl)
                except Exception as e:
                    logger.warning(f"Error renovando el lock para {destino_local}: {e}")
                    break
        except asyncio.CancelledError:
            pass

    heartbeat_task = asyncio.create_task(extend_lock_loop())
    
    try:
        yield lock
    finally:
        heartbeat_task.cancel()
        try:
            await heartbeat_task
        except asyncio.CancelledError:
            pass
        try:
            await lock.release()
        except Exception:
            pass


def asegurar_estructura_okf(base_dir: str):
    """!
    @brief Crea la estructura de directorios OKF v0.1 y archivos .gitkeep para forzar el rastreo en Git.
    """
    for folder in ["raw", "okf", "okf/concepts", "okf/entities", "okf/sources", "okf/playbooks", "bitacora", "logs"]:
        folder_path = os.path.join(base_dir, folder.replace("/", os.sep))
        os.makedirs(folder_path, exist_ok=True)
        with open(os.path.join(folder_path, ".gitkeep"), "w") as f:
            pass

async def run_git_command(*args, cwd=None):
    """!
    @brief Ejecuta un comando git de forma asíncrona.
    """
    if args and args[0] == 'push':
        # --- Doble barrera de seguridad: evitar push de tokens ---
        import re
        # Lista de expresiones regulares para tokens comunes de proveedores Git
        token_patterns = [
            r"ghp_[a-zA-Z0-9]{36}", # Token de Acceso Personal de GitHub
            r"github_pat_[a-zA-Z0-9_]{82}", # Token de Acceso Personal de grano fino de GitHub
            r"glpat-[a-zA-Z0-9\-]{20,}", # Token de Acceso Personal de GitLab
        ]
        
        # Comprobar qué se va a subir (push)
        # Normalmente origin/main..HEAD u origin/master..HEAD
        # Intentamos obtener las diferencias (diff). Si no hay upstream configurado, solo comprobamos HEAD.
        diff_proc = await asyncio.create_subprocess_exec(
            'git', 'log', '-p', 'origin/HEAD..HEAD',
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            cwd=cwd
        )
        diff_out, diff_err = await diff_proc.communicate()
        
        # También comprobamos el último commit por seguridad, en caso de que el rastreo de origin/main falle
        diff_proc_last = await asyncio.create_subprocess_exec(
            'git', 'show', 'HEAD',
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            cwd=cwd
        )
        diff_out_last, diff_err_last = await diff_proc_last.communicate()
        
        combined_diff = diff_out.decode(errors='ignore') + "\n" + diff_out_last.decode(errors='ignore')
        
        for pattern in token_patterns:
            if re.search(pattern, combined_diff):
                logger.error(f"FAIL-SAFE: Detectado posible token vivo (patrón: {pattern}) en el diff a punto de ser pusheado. Abortando push.")
                raise RuntimeError("FAIL-SAFE: No se puede hacer push porque se detectó un posible token de GitHub/GitLab en el código.")
        # --------------------------------------------------------

    process = await asyncio.create_subprocess_exec(
        'git', *args,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        cwd=cwd
    )
    stdout, stderr = await process.communicate()
    return process.returncode, stdout.decode(), stderr.decode()

async def asegurar_repo_local(repo_alumno_url: str, official_repo_url: Optional[str], destino_local: str) -> None:
    """!
    @brief Asegura que el repositorio local exista, esté actualizado y tenga configurado el remote upstream.
    
    @param repo_alumno_url URL del repositorio del alumno (origin).
    @param official_repo_url URL del repositorio oficial (upstream). Puede ser None.
    @param destino_local Ruta local donde debe alojarse el repositorio.
    """
    pat = os.getenv("GITHUB_PAT")
    
    # 1. Asegurar clonado
    if not os.path.exists(destino_local):
        if pat:
            # Inyectar credenciales en la URL si es http/https
            if repo_alumno_url.startswith("https://"):
                auth_url = repo_alumno_url.replace("https://", f"https://oauth2:{pat}@")
            else:
                auth_url = repo_alumno_url
        else:
            auth_url = repo_alumno_url

        logger.info(f"Clonando {repo_alumno_url} en {destino_local}")
        parent_dir = os.path.dirname(destino_local)
        os.makedirs(parent_dir, exist_ok=True)
        
        # Clonar repositorio con git
        process = await asyncio.create_subprocess_exec(
            'git', 'clone', auth_url, os.path.basename(destino_local),
            cwd=parent_dir,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        _, stderr = await process.communicate()
        if process.returncode != 0:
            raise RuntimeError(f"Error al clonar repositorio: {stderr.decode()}")
            
    else:
        logger.info(f"Repositorio ya existe en {destino_local}, haciendo fetch/pull")
        code, out, err = await run_git_command('fetch', 'origin', cwd=destino_local)
        if code != 0:
            raise RuntimeError(f"Error en fetch origin: {err}")
            
        code, out, err = await run_git_command('reset', '--hard', 'origin/HEAD', cwd=destino_local)
        if code != 0:
            raise RuntimeError(f"Error en reset origin/HEAD: {err}")

    # Establecer autor para los commits del bot (asegurar siempre que esté configurado)
    await run_git_command('config', 'user.name', 'LLM Wiki Assistant', cwd=destino_local)
    await run_git_command('config', 'user.email', 'bot@llm-wiki', cwd=destino_local)

    # Ignorar buffer de backfill
    exclude_path = os.path.join(destino_local, '.git', 'info', 'exclude')
    if os.path.exists(os.path.dirname(exclude_path)):
        with open(exclude_path, 'a+') as f:
            f.seek(0)
            if '.backfill.jsonl' not in f.read():
                f.write('\n.backfill.jsonl\n')

    # 2. Configurar remote upstream
    if official_repo_url:
        if pat and official_repo_url.startswith("https://"):
            official_auth_url = official_repo_url.replace("https://", f"https://oauth2:{pat}@")
        else:
            official_auth_url = official_repo_url

        # Comprobar si el upstream existe
        code, out, err = await run_git_command('remote', 'get-url', 'upstream', cwd=destino_local)
        if code == 0:
            # El upstream existe, actualizar URL
            if out.strip() != official_auth_url:
                await run_git_command('remote', 'set-url', 'upstream', official_auth_url, cwd=destino_local)
        else:
            # El upstream no existe, añadirlo
            await run_git_command('remote', 'add', 'upstream', official_auth_url, cwd=destino_local)
