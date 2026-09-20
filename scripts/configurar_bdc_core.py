"""! @file configurar_bdc_core.py
@brief Crea el repositorio oficial de una asignatura en GitHub/GitLab/Self-Hosted.

1. Crea el repositorio privado para la asignatura clonando el repositorio plantilla.
2. Marca el repositorio resultante como "template".
3. Añade a los profesores proporcionados como colaboradores con permisos "maintain".

Se ejecuta desde la terminal con el comando: 
python configurar_bdc_core.py <Asignatura> <Profesor1,Profesor2>
"""

import sys
import os
import asyncio

# para importar dependencias de src/
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../src/api'))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../src/shared'))

# Cargar .env
from dotenv import load_dotenv
load_dotenv(os.path.join(os.path.dirname(__file__), '../.env'))

from app.services.git import get_git_provider, GitProviderConfigError

async def amain():
    """!
    @brief Función principal asíncrona del script.
    @details Lee la configuración y carga el código según la plataforma que estés usando 
        (GitHub, GitLab, etc.) para crear el repositorio.
    """
    if len(sys.argv) < 3:
        print("Uso: python configurar_bdc_core.py <Asignatura> <Profesor1,Profesor2>")
        sys.exit(1)

    asignatura = sys.argv[1]
    profesores = sys.argv[2].split(',')

    try:
        # 1. Obtener el proveedor configurado
        # en src/api/app/services/git/__init__.py (devuelve una instancia de GitHubProvider, GitLabProvider o SelfHostedProvider)
        provider = get_git_provider()
        
        # 2. Crear el repositorio oficial
        print(f"Generando repositorio oficial para {asignatura}...")
        repo_url = await provider.crear_repo_oficial(asignatura, None)
        print(f"Repositorio creado exitosamente: {repo_url}")
        
        # 3. Marcar como template (solo hace falta si es github, sino no se hará nada)
        print(f"Marcando {repo_url} como template...")
        await provider.marcar_como_template(repo_url)
        
        # 4. Añadir profesores como colaboradores (con permiso maintain)
        for profe in profesores:
            profe = profe.strip()
            if not profe:
                continue
            
            print(f"Añadiendo a {profe} con permisos de maintain...")
            try:
                await provider.añadir_colaborador(repo_url, profe, "maintain")
            except Exception as e:
                print(f"  -> Error al añadir a {profe}: {e}")
                
    except GitProviderConfigError as e:
        print(f"Error de configuración del proveedor Git: {e}")
        sys.exit(1)
    except NotImplementedError as e:
        print("Error: El proveedor self-hosted no está implementado aún.")
        print("Por favor cambia proveedor_activo a github o gitlab en config.yaml.")
        sys.exit(1)
    except Exception as e:
        print(f"Error inesperado: {e}")
        sys.exit(1)

def main():
    asyncio.run(amain())

if __name__ == "__main__":
    main()
