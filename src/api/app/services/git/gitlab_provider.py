"""
Este archivo contiene toda la lógica necesaria para comunicarse con la API de GitLab.

Implementa las funciones necesarias para crear repositorios, registrar webhooks (avisos automáticos),
y añadir estudiantes a sus repositorios.
"""

import os
import httpx
import logging
from .base import GitProviderClient
from app.core.config import settings

logger = logging.getLogger(__name__)

class GitLabProvisionError(Exception):
    pass

class GitLabProvider(GitProviderClient):
    """
    Clase que gestiona la comunicación con GitLab. 
    Se encarga de crear repositorios para profesores y alumnos, y de configurarlos.
    """
    def __init__(self, config: dict):
        self.config = config
        self.org = config['git']['gitlab']['grupo_destino']
        self.api_base = config['git']['gitlab']['api_base_url']
        
        env_var = config['git']['gitlab'].get('token_env_var', 'GITLAB_TOKEN')
        # Buscamos en env_var directamente en settings, o si el propio env_var parece un token
        self.token = getattr(settings, env_var, None) or config['git']['gitlab'].get('pat')
        if not self.token and env_var.startswith("glpat-"):
            self.token = env_var
        
        if not self.token:
            raise GitLabProvisionError(f"{env_var} no está configurado")

        self.headers = {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json"
        }

    async def _get_client(self) -> httpx.AsyncClient:
        """
        Crea y devuelve un cliente HTTP configurado con las credenciales de GitLab para hacer peticiones.
        """
        return httpx.AsyncClient(base_url=self.api_base, headers=self.headers)

    async def existe_repo(self, repo_url_or_name: str) -> bool:
        """
        Comprueba si un repositorio ya existe en el grupo de GitLab.
        """
        repo_name = repo_url_or_name.split('/')[-1].replace('.git', '')
        project_path = f"{self.org}/{repo_name}".replace("/", "%2F")
        async with await self._get_client() as client:
            res = await client.get(f"/projects/{project_path}")
            return res.status_code == 200

    async def crear_repo_oficial(self, nombre_asignatura: str, template_id: str = None) -> str:
        """
        Crea el repositorio oficial a partir de una plantilla base.
        Si ya existe, devuelve su dirección de clonado sin dar error.
        """
        # En GitLab, primero hacemos fork y luego eliminamos la relación.
        repo_oficial = f"{nombre_asignatura}-Oficial"
        template = template_id or self.config['git']['gitlab']['repo_plantilla']
        template_path = f"{self.org}/{template}".replace("/", "%2F")
        
        if await self.existe_repo(repo_oficial):
            logger.info(f"El repositorio oficial GitLab {self.org}/{repo_oficial} ya existe.")
            return f"{self.api_base.split('/api')[0]}/{self.org}/{repo_oficial}.git"

        async with await self._get_client() as client:
            logger.info(f"Haciendo fork de {template_path} a {repo_oficial}...")
            # En GitLab necesitamos el ID del namespace destino para hacer fork, o pasarlo en los params
            res = await client.post(
                f"/projects/{template_path}/fork",
                json={
                    "name": repo_oficial,
                    "path": repo_oficial,
                    "namespace_path": self.org,
                    "visibility": "private"
                }
            )
            
            if res.status_code in (201, 200):
                repo_data = res.json()
                project_id = repo_data['id']
                
                # Eliminar relación de fork
                logger.info(f"Eliminando relación de fork para {repo_oficial}...")
                del_res = await client.delete(f"/projects/{project_id}/fork")
                if del_res.status_code != 204:
                    logger.warning(f"No se pudo eliminar el fork link de {repo_oficial}")
                    
                return repo_data.get("http_url_to_repo")
            else:
                raise GitLabProvisionError(f"Error al hacer fork (GitLab): {res.status_code} {res.text}")

    async def marcar_como_template(self, repo_url: str) -> None:
        """
        Configura un repositorio normal para que actúe como plantilla (Template).
        """
        # Gitlab no tiene templates como github
        pass

    async def generar_repo_alumno(self, nombre_repo: str, repo_oficial_url: str) -> str:
        """
        Crea una copia exacta (fork) de la plantilla base para un alumno específico.
        """
        if await self.existe_repo(nombre_repo):
            logger.info(f"El repositorio {self.org}/{nombre_repo} ya existe.")
            return f"{self.api_base.split('/api')[0]}/{self.org}/{nombre_repo}.git"
            
        # Generar a partir del template original en lugar del repo_oficial
        # para evitar copiar carpetas de otros profesores.
        template = self.config['git']['gitlab']['repo_plantilla']
        template_path = f"{self.org}/{template}".replace("/", "%2F")

        async with await self._get_client() as client:
            logger.info(f"Haciendo fork alumno de {template_path} a {nombre_repo}...")
            res = await client.post(
                f"/projects/{template_path}/fork",
                json={
                    "name": nombre_repo,
                    "path": nombre_repo,
                    "namespace_path": self.org,
                    "visibility": "private"
                }
            )
            
            if res.status_code in (201, 200):
                repo_data = res.json()
                project_id = repo_data['id']
                
                logger.info(f"Eliminando relación de fork para {nombre_repo}...")
                del_res = await client.delete(f"/projects/{project_id}/fork")
                if del_res.status_code != 204:
                    logger.warning(f"No se pudo eliminar el fork link de {nombre_repo}")
                    
                return repo_data.get("http_url_to_repo")
            else:
                raise GitLabProvisionError(f"Error al aprovisionar {self.org}/{nombre_repo}: HTTP {res.status_code} {res.text}")

    async def crear_commit_archivo(self, repo_url: str, path: str, content: str, message: str) -> str:
        """
        Sube o actualiza un archivo específico dentro de un repositorio.
        Si el archivo ya existe, añade el nuevo texto al final del archivo original.
        """
        repo_name = repo_url.split('/')[-1].replace('.git', '')
        project_path = f"{self.org}/{repo_name}".replace("/", "%2F")
        file_path = path.replace("/", "%2F")
        
        import base64
        
        async with await self._get_client() as client:
            # 1. Obtener la rama por defecto del proyecto
            proj_res = await client.get(f"/projects/{project_path}")
            if proj_res.status_code != 200:
                raise GitLabProvisionError(f"No se pudo acceder al proyecto {repo_name}")
            branch = proj_res.json().get("default_branch", "main")
            
            # 2. Comprobar si el archivo existe
            file_res = await client.get(f"/projects/{project_path}/repository/files/{file_path}?ref={branch}")
            
            final_content = content
            method = client.post # POST para crear nuevo
            
            if file_res.status_code == 200:
                file_data = file_res.json()
                existing_content = base64.b64decode(file_data["content"]).decode('utf-8')
                final_content = existing_content + content
                method = client.put # PUT para actualizar
                
            # 3. Guardar el archivo
            save_res = await method(
                f"/projects/{project_path}/repository/files/{file_path}",
                json={
                    "branch": branch,
                    "commit_message": message,
                    "content": final_content
                }
            )
            
            if save_res.status_code in (200, 201):
                # GitLab no devuelve el SHA del commit en esta llamada de la misma forma que GitHub,
                # pero devuelve información del archivo. Devolvemos el path como éxito.
                return save_res.json().get("file_path", path)
            else:
                raise GitLabProvisionError(f"Error guardando archivo {path} en {repo_name}: HTTP {save_res.status_code} {save_res.text}")

    async def añadir_colaborador(self, repo_url_or_name: str, username: str, permission: str = "maintain") -> None:
        """
        Invita a un usuario (alumno) a un repositorio y le da los permisos necesarios.
        """
        repo_name = repo_url_or_name.split('/')[-1].replace('.git', '')
        project_path = f"{self.org}/{repo_name}".replace("/", "%2F")
        
        # En GitLab, los permisos son enteros: 40 = Maintainer, 30 = Developer
        access_level = 40 if permission == "maintain" else 30
        
        async with await self._get_client() as client:
            # Primero buscamos el ID del usuario en GitLab
            user_res = await client.get(f"/users?username={username}")
            if user_res.status_code != 200 or not user_res.json():
                raise GitLabProvisionError(f"Usuario {username} no encontrado en GitLab.")
            
            user_id = user_res.json()[0]["id"]
            
            # Añadimos al usuario al proyecto
            res = await client.post(
                f"/projects/{project_path}/members",
                json={
                    "user_id": user_id,
                    "access_level": access_level
                }
            )
            # 201 = Creado, 409 = Ya existe
            if res.status_code not in (201, 409):
                raise GitLabProvisionError(f"Error al añadir colaborador {username} en {repo_name}: HTTP {res.status_code} {res.text}")
            logger.info(f"Colaborador {username} ({access_level}) añadido a {self.org}/{repo_name}.")
