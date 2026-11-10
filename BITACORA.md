# Desarrollo del proyecto

Pasos que se han seguido para desarrollar este proyecto, en el orden en que se construyó y probó cada pieza.

## Índice
- [Visión general y orden de construcción](#visión-general-y-orden-de-construcción)
- [1. Repositorio y estructura de carpetas](#1-repositorio-y-estructura-de-carpetas)
- [2. Base común: variables, configuración y paquete compartido](#2-base-común-variables-configuración-y-paquete-compartido)
- [3. Almacenes de datos: postgres, redis y pgvector](#3-almacenes-de-datos-postgres-redis-y-pgvector)
- [4. mapeo-api](#4-mapeo-api)
- [5. Matrix: synapse y element](#5-matrix-synapse-y-element)
- [6. Moodle y el plugin block_bdc](#6-moodle-y-el-plugin-block_bdc)
- [7. Bot: maubot y sync-workers](#7-bot-maubot-y-sync-workers)
- [8. metrics-api](#8-metrics-api)
- [9. metrics-worker](#9-metrics-worker)
- [10. frontend](#10-frontend)
- [11. backup](#11-backup)
- [12. Orquestación: instalar.sh y limpiar.sh](#12-orquestación-instalarsh-y-limpiarsh)

---

## Visión general y orden de construcción

Tenemos los siguientes servicios: **Moodle** (cursos y usuarios), **Matrix** (chat), **Git** (un repositorio por alumno) y un **LLM** (respuestas y resúmenes).  `mapeo-api`, los conecta, guardando la relación *alumno ↔ repositorio ↔ sala de chat*.

```text
Moodle ──(crea sala y mapeo)──► mapeo-api ──► Git (GitHub/GitLab/self-hosted)
   │                               ▲  ▲
   │ login                         │  └──── metrics-api ◄── frontend (profesorado)
   ▼                               │              ▲
Synapse/Element ◄── maubot ────────┘              │
                      │                           │
                      └─► Redis ─► sync-workers ──┘ (PII) ─► Git
                                                  metrics-worker (audita Git vs BD)
```

Seguiremos las siguientes fases:

1. **Repositorio y estructura de carpetas:** `git init` y árbol de directorios del proyecto.
2. **Base común:** `.gitignore`, `.env.example`, `config/config.yaml.example`, paquete compartido `shared_pkg` (`config_loader`, `okf_contract`) y esqueleto del `docker-compose.yml`.
3. **Almacenes de datos:** `postgres` (mapeo, métricas y Synapse), `redis` (cola de tareas y bloqueos) y `pgvector` (búsqueda semántica).
4. **`mapeo-api`**:
   - Esqueleto FastAPI, `/health` y autenticación por token.
   - Base de datos, modelos y migraciones con Alembic.
   - Crear y consultar mapeos.
   - Proveedor Git (GitHub, GitLab, autoalojado) y aprovisionamiento de repositorios.
   - Cursos y repositorio oficial, usuario Git y colaboradores.
   - Webhook de sincronización, eventos del bot y auditoría.
   - Token SSO para Matrix, mantenimiento de la API, pruebas y scripts de aprovisionamiento.
5. **Matrix:** `synapse` (servidor de chat sobre `postgres`) y `element` (cliente web con página `sso.html`).
6. **Moodle y plugin `block_bdc`:**
   - Moodle en Docker con MariaDB y PHP 8.3.
   - Esqueleto del bloque y botón **Acceder**.
   - Repositorio oficial al crear un curso (`observer`).
   - Clientes de `mapeo-api` y de la API de administración de Synapse.
   - `view.php` (sala, mapeo y redirección a Element) y formulario de usuario Git.
   - Login de Matrix contra Moodle (`auth.php` y `rest_auth_provider.py`).
7. **Bot (`maubot` y `sync-workers`):**
   - Imagen y esqueleto del plugin.
   - Clientes de `mapeo-api` y de LLM, y almacén vectorial.
   - Utilidades Git y lectura e indexado del repositorio (RAG).
   - Respuesta a preguntas, comandos e ingesta de ficheros.
   - Workers con Redis y protección de datos personales (PII).
8. **`metrics-api`:** métricas, login con JWT y permisos por curso, discrepancias, interacciones y conceptos, rúbricas y agente evaluador con IA, y bóveda de PII.
9. **`metrics-worker`:** consumo de eventos, reconciliación del historial de Git con la base de datos y carga histórica.
10. **`frontend`:** dashboard del profesorado (React, TypeScript y Vite) con login, rutas protegidas, pantallas y pruebas e2e.
11. **`backup`:** copia diaria de `postgres` y `redis` con política de retención.
12. **Orquestación:** `instalar.sh` (despliegue completo)

---

## 1. Repositorio y estructura de carpetas

1. **Inicialización del repositorio Git:**
   ```bash
   git init
   ```

2. **Creación de la estructura de carpetas y archivos iniciales:**
   
```text
llm-wiki-assistant/
├── config/                 # Configuración del proyecto
├── scripts/                # Scripts auxiliares de despliegue y mantenimiento
├── src/                    # Código fuente de los distintos microservicios
│   ├── api/                # API de mapeo (mapeo-api: Alumno ↔ Git ↔ Matrix)
│   ├── backup/             # Copias de seguridad automáticas de las BDs
│   ├── bot/                # Plugin de Maubot y sync-worker
│   ├── frontend/           # Dashboard web del profesorado (React 19 + TypeScript + Vite)
│   ├── matrix/             # Infraestructura de chat: Synapse y Element
│   ├── metrics-api/        # Métricas
│   ├── metrics-worker/     # Proceso de auditoría y reconciliación de historial Git con BD
│   ├── moodle/             # Entorno Moodle y plugin personalizado (block_bdc)
│   └── shared/             # Librerías y paquetes Python compartidos
├── docker-compose.yml      # Despliegue y orquestación de todos los microservicios
├── .env.example            # Plantilla de variables de entorno y contraseñas
├── .gitignore              # Archivos y carpetas ignorados por Git
└── instalar.sh             # Script principal de instalación y configuración
```


---

## 2. Base común: variables, configuración y paquete compartido


### 2.1. .gitignore
Primero añadimos las variables de entorno, Python y editores:

```
# Entorno y variables secretas
.env
*.env
config/config.yaml

# Archivos de registro
*.log

# Archivos compilados de Python y entornos virtuales
__pycache__/
*.py[cod]
*$py.class
.venv/
venv/
env/
ENV/

# Configuración de editores / IDEs
.vscode/
.idea/
*.swp
*.swo

# Archivos del sistema operativo
.DS_Store
Thumbs.db
```

### 2.2 .env.example
```
# ==========================================================================
# ARCHIVO DE CONFIGURACIÓN DE ENTORNO — .env.example
# ==========================================================================
#   cp .env.example .env
#
# LEYENDA:
#   [CAMBIAR]        -> Debes cambiar este valor antes de desplegar.
#   [AUTOGENERADO]   -> Lo genera el script ./instalar.sh automáticamente.
#   [INTERNO DOCKER] -> URL usada solo entre contenedores.
#                       No modificar (se usan internamente en docker)
#   (opcional)       -> Solo necesario si activas esa funcionalidad.
# ==========================================================================

# --------------------------------------------------------------------------
# CONFIGURACIÓN GENERAL
# --------------------------------------------------------------------------
# Nombre de dominio o IP del servidor donde se desplegará el proyecto.
DOMAIN=localhost
```

### 2.3 src/shared/shared_pkg y pyproject.toml

- `shared_pkg` sirve para reutilizar código y sustituir las variables del .env al config.yaml
   - config_loader.py: Sustituye variables del .env al config.yaml
- `pyproject.toml` para configurar cómo empaquetar el código de shared_pkg

### docker-compose.yml

Creamos lo mínimo:
```
services:

volumes:

networks:
bdc-net:
```

## 3. Almacenes de datos: postgres, redis y pgvector

### 3.1. Postgres

Guardará las tablas de `mapeo-api`, las tablas de `metrics-api` y las internas del servidor del chat de `synapse`.

Para ello, añadimos al `.env.example`:

```
# --------------------------------------------------
# POSTGRES — Base de datos de mapeo-api, metrics-api y Synapse
# --------------------------------------------------
# nombre para docker
POSTGRES_NOMBRE_CONTENEDOR=moodle-matrix-dev-postgres-1
# nombre del usuario para la BD
POSTGRES_USER=mapeo_user
# contraseña para la BD
POSTGRES_PASSWORD=mapeo_db_pass
# nombre de la BD (se crea al arrancar el contenedor por primera vez)
POSTGRES_DB=mapeo_db
# Puerto en el que escucha el servicio de PostgreSQL dentro de Docker
POSTGRES_PUERTO_CONTENEDOR=5432
```

Y añadir el servicio de postgres en `docker-compose.yml`:

- **Nota**: Añadimos pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB} cada 10 segundos porque sino, 
la API intentará conectarse a Postgres antes de que haya terminado de inicializarse.

- Volumes son como "disco duros externos" para que no se borren los datos al hacer `docker compose down`

```
services:
  postgres:
    image: postgres:16-alpine
    container_name: ${POSTGRES_NOMBRE_CONTENEDOR}
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    networks:
      - default
      - bdc-net
    volumes:
      - postgres_api_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  postgres_api_data:

networks:
  bdc-net:
```

### 3.2 Redis

Para enncolar los trabajos y que no se ejecuten dos procesos a la vez (por ejemplo dos commit a la vez).

- **Nota**: ``PUERTO_HOST`` es el puerto del host (eg de mi ordenador) y ``PUERTO_CONTENEDOR`` es el de Docker

```
# --------------------------------------------------
# REDIS - Cola de tareas asíncronas (workers del bot)
# --------------------------------------------------
REDIS_NOMBRE_CONTENEDOR=moodle-matrix-dev-redis-1
REDIS_PUERTO_HOST=6379
REDIS_PUERTO_CONTENEDOR=6379
```

Y añadimos `redis` a `docker-compose.yml`:

- Comando: ``["redis-server", "--appendonly", "yes"]``. El flag ``appendonly yes`` activa la persistencia en disco (AOF) para que, si el contenedor se reinicia, no se pierdan los logs de interacción que estaban en la cola esperando a subirse a Git.

```
services:
   redis:
      image: redis:7
      container_name: ${REDIS_NOMBRE_CONTENEDOR}
      command: ["redis-server", "--appendonly", "yes"]
      ports:
         - "${REDIS_PUERTO_HOST}:${REDIS_PUERTO_CONTENEDOR}"
      networks:
         - default
         - bdc-net
      volumes:
         - redis_data:/data
      healthcheck:
         test: ["CMD", "redis-cli", "ping"]
         interval: 10s
         timeout: 5s
         retries: 5
volumes:
   redis_data:
```

### 3.3 Pgvector

Para convertir los apuntes Markdown en embeddings y buscar por RAG.
`pgvector` es `PostgreSQL` con una extensión que añade un tipo de columna ``vector(N)`` y operadores para buscar por similitud.

```
# --------------------------------------------------
# PGVECTOR - Base de datos vectorial para el bot LLM
# --------------------------------------------------
PGVECTOR_NOMBRE_CONTENEDOR=moodle-matrix-dev-pgvector-1
PGVECTOR_PUERTO_HOST=5432
PGVECTOR_PUERTO_CONTENEDOR=5432
PGVECTOR_USER=llm_wiki
PGVECTOR_PASSWORD=llm_wiki_pass
PGVECTOR_DB=vector_store
```

Añadimos `pgvector` a `docker-compose.yml`:

```
services:
   pgvector:
    image: pgvector/pgvector:pg16
    container_name: ${PGVECTOR_NOMBRE_CONTENEDOR}
    environment:
      POSTGRES_USER: ${PGVECTOR_USER}
      POSTGRES_PASSWORD: ${PGVECTOR_PASSWORD}
      POSTGRES_DB: ${PGVECTOR_DB}
    ports:
      - "${PGVECTOR_PUERTO_HOST}:${PGVECTOR_PUERTO_CONTENEDOR}"
    volumes:
      - pgvector_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${PGVECTOR_USER} -d ${PGVECTOR_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
   pg_vector_data:

```


## 4. Mapeo-Api

### 4.1 FastApi

4.1.1. Creamos las carpetas ``src/api/app/core`` (para configuración, conexión a la base de datos (aquí, el pgvector) y utilidades base) ``src/api/tests``

4.1.2. Creamos `src/api/requirements.txt` con las dependencias que vamos a necesitar: ``fastapi, uvicorn[standard], sqlmodel, psycopg2-binary, pydantic-settings, httpx, alembic, pytest, pytest-asyncio, pyyaml, redis, rq``.

4.1.3. Creamos ``src/api/app/core/config.py``: 
Define una clase ``Settings`` que, al arrancar la API, lee las variables del archivo .env, comprueba que las obligatorias existen y tienen el tipo correcto (si falta alguna, la API ni arranca), y deja todo accesible como settings.DATABASE_URL, settings.DOMAIN,...

4.1.4 Creamos `src/api/app/main.py`:
Es el punto de entrada de la aplicación FastAPI. Aquí definimos:
- El ciclo de vida de la aplicación (`lifespan`) para verificar la conexión a la base de datos y la inicialización de colas de Redis.
- El middleware `SunsetMiddleware` para gestionar la transición suave de endpoints antiguos hacia la ruta versionada `/v1/` añadiendo la cabecera HTTP `Sunset: Wed, 18 Feb 2027 00:00:00 GMT`.
- Los manejadores de excepciones (`StarletteHTTPException` y `RequestValidationError`) para estandarizar las respuestas de error en formato JSON RFC 7807 (`type`, `title`, `status`, `detail`, `instance`).
- El endpoint `GET /health` que verifica el estado del servicio y de la base de datos para el `healthcheck` de Docker.
- La función de seguridad `verify_token` basada en `HTTPBearer`, que valida que toda petición administrativa incluya la cabecera `Authorization: Bearer <MAPEO_API_TOKEN>`.

### 4.2 Base de datos, modelos y migraciones con Alembic

4.2.1. Creamos `src/api/app/db.py`:
Configura el motor de SQLAlchemy contra PostgreSQL (`DATABASE_URL`), la factoría de sesiones `sessionmaker` y define la tabla `mapeos`:
- `id` (entero, clave primaria autoincremental).
- `moodle_user_id` (entero): ID numérico del usuario en Moodle.
- `moodle_course_id` (entero): ID del curso en Moodle. Incluye una restricción única `uq_user_course` para impedir registros duplicados del mismo alumno en la misma asignatura.
- `repo_url` (texto): URL del repositorio Git asignado al alumno o profesor.
- `official_repo_url` (texto): URL del repositorio oficial de la asignatura que sirve de plantilla base.
- `matrix_room_id` (texto): ID interno de la sala de chat en Matrix (`!room_id:dominio`).
- `git_username` (texto, opcional): Usuario del alumno o profesor en GitHub/GitLab para darle permisos de colaborador.
- `is_teacher` (entero): Flag que indica si el mapeo corresponde a un profesor (1) o a un alumno (0).
- `moodle_username` (texto) y `moodle_course_name` (texto): Nombres legibles para facilitar búsquedas y reportes.
- `estado` (Enum): `PENDIENTE_GIT` (creado pero esperando que Git termine de clonar) o `ACTIVO` (repositorio y sala listos para usarse).

4.2.2. Creamos `src/api/app/models.py`:
Define los esquemas Pydantic para validar los datos que entran y salen por la API:
- `MapeoBase`, `MapeoCreate` y `MapeoRead`: Para crear y devolver mapeos alumno-curso-sala.
- `CursoCreate`: Para la provisión del repositorio oficial de una asignatura.
- `GitUsernameSyncRequest` y `GitUsernameSyncResponse`: Para registrar o cambiar el usuario de Git y propagar colaboradores.
- `MatrixTokenRequest` y `MatrixTokenResponse`: Para la generación de tokens de auto-login SSO en Matrix.

4.2.3. Inicializamos las migraciones con Alembic:
```bash
cd src/api
alembic init alembic
```
Configuramos `alembic.ini` y `src/api/alembic/env.py` para que lea la cadena de conexión de `settings.DATABASE_URL` y detecte automáticamente los modelos de `src/api/app/db.py`. Creamos las versiones de migración en `src/api/alembic/versions/` para versionar los cambios del esquema de la base de datos de manera reproducible.

### 4.3 Proveedores Git y aprovisionamiento de repositorios

Para no acoplar el sistema exclusivamente a GitHub y permitir que funcione con GitLab o servidores Git propios, implementamos un patrón factoría en `src/api/app/services/git/`:

4.3.1. Creamos `src/api/app/services/git/base.py`:
Define la clase abstracta `GitProviderBase` con las operaciones que cualquier proveedor de Git debe implementar:
- `crear_repo_oficial(course_shortname, template_id)`: Crea el repositorio oficial de la asignatura.
- `marcar_como_template(repo_url)`: Marca el repositorio como plantilla pública o interna para que los alumnos puedan clonarlo.
- `generar_repo_alumno(student_repo_name, official_repo_name)`: Crea el repositorio personal del alumno a partir de la plantilla oficial.
- `añadir_colaborador(repo_url, git_username, permission)`: Otorga permisos en el repositorio (permiso de escritura al alumno en su repositorio y permiso al profesor en el repositorio oficial).
- `eliminar_colaborador(repo_url, git_username)`: Retira el acceso a un colaborador si el usuario desvincula su cuenta de Git.

4.3.2. Implementamos los adaptadores específicos:
- `github_provider.py`: Utiliza la API REST de GitHub con un Token de Acceso Personal (`GITHUB_PAT`), gestionando organizaciones, repositorios de plantilla y colaboradores.
- `gitlab_provider.py`: Implementación para instancias de GitLab Cloud o Autoalojadas utilizando grupos (`grupo_destino`).
- `self_hosted_provider.py`: Para proveedores Git genéricos o servidores internos Gitea/Forgejo.

4.3.3. Creamos `src/api/app/services/git/__init__.py`:
Contiene la función factoría `get_git_provider()`, que lee `config/config.yaml` y devuelve la instancia del proveedor configurado bajo la clave `git.proveedor_activo`.

### 4.4 Endpoints de mapeos, cursos y token SSO

Implementamos los endpoints en `src/api/app/main.py`:

4.4.1. `POST /v1/mapeos`:
- Recibe los datos del alumno o profesor desde el plugin de Moodle.
- Guarda el registro en la base de datos en estado `PENDIENTE_GIT`.
- Si el usuario es un **profesor**, no se crea un fork: se le asigna directamente el repositorio oficial (`[shortname]-Oficial`) como colaborador.
- Si es un **alumno**, se llama al proveedor Git para crear su repositorio personal (`[shortname]-[username]`) a partir de la plantilla oficial.
- Si se proporciona `git_username`, se añade al usuario como colaborador en Git de forma no bloqueante.
- Si es un alumno, encola un trabajo en Redis mediante RQ (`sync_worker.tasks.sync_repo_task`) para sincronizar el contenido oficial inicial (`material-oficial/`).

4.4.2. `GET /v1/mapeos`:
Permite consultar mapeos filtrando por `moodle_user_id`, `moodle_course_id`, `moodle_username` o `matrix_room_id`.

4.4.3. `POST /v1/cursos`:
Aprovisiona la plantilla oficial del curso en el proveedor Git (`[shortname]-Oficial`) y la marca como plantilla.

4.4.4. `POST /v1/sync/git-username`:
Permite que un alumno o profesor declare o modifique su usuario de Git desde el formulario de Moodle. La API actualiza el registro en la base de datos, retira el colaborador anterior en Git y añade el nuevo.

4.4.5. `POST /v1/sync/oficial-updated`:
Webhook protegido con firma HMAC SHA-256 (`x-hub-signature-256`) que recibe notificaciones de Git cuando el profesor sube cambios al repositorio oficial y encola la sincronización hacia todos los repositorios de alumnos matriculados.

4.4.6. `POST /v1/auth/matrix-token`:
Permite el inicio de sesión único (SSO) transparente en Element. Genera un token aleatorio seguro (`secrets.token_urlsafe(32)`) y lo inserta directamente en la tabla `login_tokens` de Synapse con una validez de 2 minutos. Devuelve el token a Moodle para que redirija al usuario hacia Element con `?loginToken=...`.

### 4.5 Dockerfile y servicio mapeo-api en docker-compose

4.5.1. Creamos `src/api/Dockerfile`:
```dockerfile
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential libpq-dev git curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD ["sh", "-c", "alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port 8000"]
```

4.5.2. Añadimos las variables de entorno en `.env.example`:
```bash
# --------------------------------------------------
# MAPEO API — Orquestador Alumno ↔ Git ↔ Matrix
# --------------------------------------------------
MAPEO_API_NOMBRE_CONTENEDOR=moodle-matrix-dev-mapeo-api-1
MAPEO_API_PUERTO_HOST=8001
MAPEO_API_PUERTO_CONTENEDOR=8000
MAPEO_API_TOKEN=mapeo_api_secret_token_12345
MAPEO_API_URL=http://mapeo-api:${MAPEO_API_PUERTO_CONTENEDOR}
```

4.5.3. Declaramos `mapeo-api` en `docker-compose.yml`:
```yaml
services:
  mapeo-api:
    build:
      context: ./src/api
      dockerfile: Dockerfile
    container_name: ${MAPEO_API_NOMBRE_CONTENEDOR}
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    ports:
      - "${MAPEO_API_PUERTO_HOST}:${MAPEO_API_PUERTO_CONTENEDOR}"
    environment:
      - DATABASE_URL=${DATABASE_URL}
      - DOMAIN=${DOMAIN}
      - MAPEO_API_TOKEN=${MAPEO_API_TOKEN}
      - REDIS_URL=redis://redis:6379/0
      - GITHUB_PAT=${GITHUB_PAT}
    volumes:
      - ./src/api:/app
      - ./config:/config
      - ./src/shared:/shared-pkg:ro
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - default
      - bdc-net
```

---

## 5. Matrix: synapse y element

### 5.1 Synapse

Synapse es el servidor de chat de referencia para el protocolo Matrix. En lugar de almacenar sus datos en SQLite (que no escala para concurrencia), lo conectamos a la base de datos `postgres` existente.

5.1.1. Configuramos la plantilla `src/matrix/synapse-data/homeserver.yaml.example`:
- `server_name: "${DOMAIN}"`: Dominio federado del servidor.
- Base de datos conectada a PostgreSQL:
  ```yaml
  database:
    name: psycopg2
    args:
      user: "${POSTGRES_USER}"
      password: "${POSTGRES_PASSWORD}"
      database: "${POSTGRES_DB}"
      host: "postgres"
      port: 5432
      cp_min: 5
      cp_max: 10
  ```
- Activación de endpoints de administración y registro con token compartido (`SYNAPSE_REGISTRATION_SHARED_SECRET`).

5.1.2. Módulo de autenticación contra Moodle: `src/matrix/synapse-custom/rest_auth_provider.py`:
Permite que cualquier usuario creado en Moodle pueda iniciar sesión en Matrix con su mismo usuario y contraseña. Synapse delega la comprobación enviando una petición HTTP POST al endpoint de Moodle (`/blocks/bdc/api/auth.php`). Si Moodle confirma que la contraseña es correcta, Synapse crea o valida la cuenta del usuario en Matrix al vuelo.

5.1.3. Declaramos `synapse` en `docker-compose.yml`:
```yaml
services:
  synapse:
    image: matrixdotorg/synapse:latest
    container_name: ${SYNAPSE_NOMBRE_CONTENEDOR}
    depends_on:
      postgres:
        condition: service_healthy
    ports:
      - "${SYNAPSE_PUERTO_HOST}:8008"
    volumes:
      - ./src/matrix/synapse-data:/data
    networks:
      - default
      - bdc-net
```

### 5.2 Element Web

Element es el cliente web que usarán profesores y alumnos para chatear con el bot.

5.2.1. Creamos la plantilla `src/matrix/element/config.json.template`:
Define el servidor de inicio predeterminado apuntando a la URL pública de Synapse:
```json
{
  "default_server_config": {
    "m.homeserver": {
      "base_url": "${SYNAPSE_URL}",
      "server_name": "${DOMAIN}"
    }
  },
  "disable_custom_urls": true
}
```

5.2.2. Pasarela de auto-login: `src/matrix/element/sso.html`:
Página puente para permitir que al hacer clic en Moodle en "Acceder al chat", el usuario entre logueado directamente sin ver la pantalla de login de Element:
- Lee la URL del homeserver desde `config.json`.
- Establece la clave `mx_sso_hs_url` en el `localStorage` del navegador para que Element sepa contra qué servidor autenticarse.
- Redirige inmediatamente a `/#/?loginToken=<token>` para que Element consuma el `loginToken` temporal de un solo uso emitido por `mapeo-api`.

5.2.3. Plantilla Nginx de Element: `src/matrix/element/default.conf.template`:
Configura el servidor web de Element sirviendo la aplicación SPA y añadiendo directivas `no-cache` específicas para `/sso.html` y `config.json`, evitando problemas de caché de tokens en los navegadores.

5.2.4. Declaramos `element` en `docker-compose.yml`:
```yaml
services:
  element:
    image: vectorim/element-web:latest
    container_name: ${ELEMENT_NOMBRE_CONTENEDOR}
    depends_on:
      - synapse
    ports:
      - "${ELEMENT_PUERTO_HOST}:80"
    volumes:
      - ./src/matrix/element/config.json:/app/config.json:ro
      - ./src/matrix/element/sso.html:/app/sso.html:ro
      - ./src/matrix/element/default.conf.template:/etc/nginx/templates/default.conf.template:ro
    networks:
      - default
      - bdc-net
```

---

## 6. Moodle y el plugin block_bdc

### 6.1 Entorno Moodle en Docker y fix_wwwroot.php

6.1.1. Dockerfile personalizado `src/moodle/Dockerfile`:
- Partimos de la imagen `bitnamilegacy/moodle:latest`.
- Instalamos los repositorios oficiales de PHP (Sury) y actualizamos a **PHP 8.3** parcheado contra vulnerabilidades de ejecución remota (PHP2Shell).
- Configuramos un enlace simbólico para que el plugin `/moodle-custom-plugin` quede montado en `/opt/bitnami/moodle/blocks/bdc`.
- Copiamos `src/moodle/fix_wwwroot.php` y lo inyectamos en `/opt/bitnami/scripts/moodle/setup.sh` para que se ejecute en cada arranque del contenedor.

6.1.2. Script `src/moodle/fix_wwwroot.php`:
Resuelve de forma definitiva los **Issues #2 y #4** (evitar modificar `config.php` a mano):
- Lee la variable de entorno `MOODLE_URL` del archivo `.env`.
- Si `MOODLE_URL` está definida (ej. `https://devceprud.ugr.es`), sustituye el bloque estático de Bitnami por dicha URL y activa automáticamente `$CFG->sslproxy = true;` y `$CFG->reverseproxy = true;` si empieza por `https://`.
- Si no está definida, analiza dinámicamente si la petición llega con `HTTPS == on` o mediante cabeceras de proxy inverso (`HTTP_X_FORWARDED_PROTO == https` y `HTTP_X_FORWARDED_HOST`), configurando los proxies correctamente y evitando enlaces rotos hacia `127.0.0.1:8080`.

6.1.3. Declaramos `moodle` y `mariadb` en `docker-compose.yml`:
```yaml
services:
  mariadb:
    image: bitnami/mariadb:10.11
    container_name: ${MARIADB_NOMBRE_CONTENEDOR}
    environment:
      - MARIADB_USER=${MOODLE_DATABASE_USER}
      - MARIADB_PASSWORD=${MOODLE_DATABASE_PASSWORD}
      - MARIADB_DATABASE=${MOODLE_DATABASE_NAME}
      - MARIADB_ROOT_PASSWORD=${MARIADB_ROOT_PASSWORD}
    volumes:
      - mariadb_data:/bitnami/mariadb
    networks:
      - default
      - bdc-net

  moodle:
    build:
      context: ./src/moodle
      dockerfile: Dockerfile
    container_name: ${MOODLE_NOMBRE_CONTENEDOR}
    depends_on:
      - mariadb
    ports:
      - "${MOODLE_PUERTO_HOST}:${MOODLE_PUERTO_CONTENEDOR}"
    environment:
      - MOODLE_DATABASE_HOST=mariadb
      - MOODLE_DATABASE_USER=${MOODLE_DATABASE_USER}
      - MOODLE_DATABASE_PASSWORD=${MOODLE_DATABASE_PASSWORD}
      - MOODLE_DATABASE_NAME=${MOODLE_DATABASE_NAME}
      - MOODLE_URL=${MOODLE_URL}
      - MAPEO_API_URL=${MAPEO_API_URL}
      - MAPEO_API_TOKEN=${MAPEO_API_TOKEN}
    volumes:
      - moodle_data:/bitnami/moodle
      - moodledata_data:/bitnami/moodledata
      - ./src/moodle/block_bdc:/moodle-custom-plugin
    networks:
      - default
      - bdc-net
```

### 6.2 Plugin block_bdc

El plugin de Moodle `block_bdc` (Bloque de Chat y Repositorio BDC) es el nexo de unión que ve el usuario en la interfaz del curso.

6.2.1. Estructura de carpetas de `src/moodle/block_bdc/`:
```text
block_bdc/
├── api/            # auth.php (endpoint REST para validación de contraseñas de Synapse)
├── classes/        # observer.php (escucha eventos de creación de cursos y matrículas)
├── db/             # access.php (permisos) y events.php (registro de observadores de eventos)
├── lang/           # Cadenas de idioma traducibles (en, es)
├── lib/            # Clientes mapeo_client.php y synapse_admin_client.php
├── block_bdc.php   # Renderizado visual del bloque en el lateral del curso
├── github_username.php # Formulario para vincular la cuenta de Git
├── version.php     # Metadatos y versión del componente de Moodle
└── view.php        # Controlador principal de redirección y auto-login
```

6.2.2. Clientes auxiliares en `src/moodle/block_bdc/lib/`:
- `mapeo_client.php`: Gestiona llamadas cURL seguras contra `mapeo-api` para consultar mapeos (`get_mapeo`), crearlos (`create_mapeo`) y solicitar tokens temporales SSO (`get_matrix_login_token`).
- `synapse_admin_client.php`: Interactúa con la Admin API de Synapse (`/_synapse/admin/v1/`) usando el token de administración para crear salas privadas, asignarles nombre y configurar alias si aún no existen.

6.2.3. Flujo interactivo de `view.php`:
Cuando un profesor o alumno hace clic en el botón **"Acceder al chat"** dentro del curso:
1. Comprueba la sesión activa de Moodle y los permisos del usuario en el curso.
2. Comprueba si el usuario tiene rol docente (`moodle/course:update` o `moodle/grade:edit`).
3. Consulta a `mapeo-api` si ya existe un mapeo para ese usuario y curso:
   - Si no existe la sala de Matrix, `synapse_admin_client` crea una nueva sala con el nombre de la asignatura.
   - Llama a `create_mapeo` en `mapeo-api` indicando si es profesor o alumno.
4. Solicita a `mapeo-api` un `login_token` temporal para el usuario.
5. Redirige automáticamente al navegador a `http://<ELEMENT_URL>/sso.html?loginToken=<TOKEN>`, iniciando la sesión en Element de manera inmediata y sin solicitar contraseñas.

6.2.4. Formulario de cuenta Git: `src/moodle/block_bdc/github_username.php`:
Permite que el estudiante o profesor introduzca su nombre de usuario de GitHub/GitLab. Al guardar, notifica a `POST /v1/sync/git-username` en `mapeo-api`, añadiéndolo al instante como colaborador en su repositorio.

6.2.5. Eventos y sincronización automática:
- En `src/moodle/block_bdc/db/events.php` registramos los eventos:
  - `\core\event\course_created`: Creación de un curso.
  - `\core\event\user_enrolment_created`: Matriculación de un usuario.
  - `\core\event\role_assigned`: Asignación de rol de profesor.
- En `src/moodle/block_bdc/classes/observer.php`:
  - Al crearse un curso, notifica a `mapeo-api` (`POST /cursos`) para crear la plantilla oficial en Git y registra al profesor creador en `mapeo-api` como docente.
  - Al matricular a un profesor o asignarle permisos de edición, lo da de alta automáticamente en `mapeo-api` para que la asignatura aparezca en su dashboard de métricas sin esperas.

---

## 7. Bot: maubot y sync-workers

### 7.1 Maubot y el plugin llm-wiki-assistant-plugin

Maubot es un framework en Python para bots de Matrix.

7.1.1. Configuramos `src/bot/config.yaml.example`:
- Parámetros de conexión a Matrix (`homeserver`, usuario del bot `@llm_wiki_assistant:dominio`, contraseña o token de acceso).
- Configuración de modelos LLM (OpenAI, Google Gemini o modelos locales Ollama).
- Parámetros de RAG: longitud de fragmentos (`chunk_size`), solapamiento (`chunk_overlap`) y número máximo de fragmentos recuperados (`k=4`).

7.1.2. Módulos y mixins del bot (`src/bot/llm-wiki-assistant-plugin/`):
- `assistant.py`: Clase principal del plugin que hereda de `Plugin`. Escucha los eventos de mensaje (`m.room.message`) en las salas de Matrix, verifica si proceden de un usuario real (no bucle con mensajes del propio bot) y gestiona los comandos (`!ayuda`, `!sync`, `!reset`).
- `mixins/mapeo_client.py`: Consulta a `mapeo-api` para averiguar a qué alumno, curso y repositorio Git corresponde la sala de chat actual.
- `mixins/repo_reader.py`: Descarga y lee los ficheros Markdown del repositorio del alumno y el fichero directriz `AGENTS.md` subido por el profesorado.
- `mixins/vector_store.py`: Divide los apuntes Markdown en fragmentos, calcula sus representaciones vectoriales (*embeddings*) y los indexa en `pgvector` mediante búsquedas por similitud de coseno (`<=>`).
- `mixins/llm_clients.py`: Cliente unificado que soporta Gemini, OpenAI y Ollama para formular la respuesta del bot inyectando el contexto de los apuntes y las instrucciones del profesor.

### 7.2 sync-workers y protección de datos (PII Guard)

7.2.1. Tareas en segundo plano con Redis y RQ (`src/bot/llm-wiki-assistant-plugin/sync_worker/tasks.py`):
Para evitar bloquear la respuesta del chat en Matrix, las operaciones pesadas de Git y de red se encolan en Redis y son procesadas por los contenedores `sync-worker-1` y `sync-worker-2`:
- `sync_repo_task`: Inyecta la carpeta `material-oficial/` en el repositorio del alumno o crea la carpeta de apuntes de profesores.
- `save_interaction_task`: Registra el historial de preguntas del alumno y respuestas del bot, subiendo un commit estructurado al repositorio Git y notificando el evento a `metrics-api`.

7.2.2. Protección de datos personales: `src/bot/llm-wiki-assistant-plugin/sync_worker/pii_guard.py`:
Garantiza el cumplimiento de privacidad antes de que cualquier interacción se guarde o analice:
- Utiliza **Microsoft Presidio** y modelos de lenguaje de spaCy (`es_core_news_lg` para español y `en_core_web_lg` para inglés).
- Detecta entidades sensibles: DNI/NIE, nombres de personas, direcciones de correo electrónico, números de teléfono y direcciones IP.
- Pseudonimiza los valores reemplazándolos por tokens cifrados o identificadores seguros antes de almacenar el log en Git o en la base de datos de métricas.

7.2.3. Declaramos `maubot` y los `sync-workers` en `docker-compose.yml`:
```yaml
services:
  maubot:
    image: dock.mau.dev/maubot/maubot:latest
    container_name: ${MAUBOT_NOMBRE_CONTENEDOR}
    depends_on:
      - synapse
      - redis
      - pgvector
    ports:
      - "${MAUBOT_PUERTO_HOST}:29316"
    volumes:
      - ./src/bot:/data
    networks:
      - default
      - bdc-net

  sync-worker-1:
    build:
      context: ./src/api
      dockerfile: Dockerfile
    container_name: moodle-matrix-dev-sync-worker-1
    command: ["rq", "worker", "-u", "redis://redis:6379/0", "sync_tasks"]
    depends_on:
      - redis
      - mapeo-api
    volumes:
      - ./src/bot/llm-wiki-assistant-plugin:/app/llm-wiki-assistant-plugin
      - ./config:/config
    networks:
      - default
      - bdc-net
```

---

## 8. metrics-api

`metrics-api` es el microservicio en FastAPI responsable de la auditoría, análisis de interacciones, gestión de rúbricas y el agente evaluador con IA.

### 8.1 Base de datos y migraciones (esquema metrics)

8.1.1. Configuración de PostgreSQL en `src/metrics-api/alembic/`:
Para aislar completamente las tablas de métricas respecto a las de `mapeo-api` y `synapse`, utilizamos un esquema dedicado de PostgreSQL llamado `metrics`:
- `interacciones`: Registro de cada pregunta del alumno y respuesta del asistente, fecha, tipo (`chat`, `quiz`, `consulta`), conceptos extraídos y metadatos.
- `eventos_sync`: Trazabilidad de los commits de sincronización procesados.
- `discrepancias_auditoria`: Commits o modificaciones detectadas en Git que no cuadran con las registradas por la plataforma.
- `refresh_tokens`: Sesiones de usuario persistidas con hashes SHA-256 criptográficos y expiración a 7 días.
- `rubricas`: Rúbricas de evaluación configuradas por el profesor por curso o a nivel global.
- `auditoria_acceso`: Registro de inicios de sesión y accesos no autorizados.
- `vault_pii`: Almacén con cifrado simétrico (Fernet) para la recuperación controlada de datos de identidad disociados.

### 8.2 Autenticación JWT y sesiones seguras

8.2.1. Inicio de sesión: `POST /v1/token`:
- Recibe las credenciales de Moodle (`username` y `password`).
- Valida la contraseña directamente contra el servicio móvil de Moodle (`MOODLE_AUTH_URL`).
- Si las credenciales son válidas, consulta en `mapeo-api` los cursos asignados al usuario y si posee rol docente (`is_teacher`).
- Emite un **Access Token JWT** firmado con clave secreta HS256 con validez de 15 minutos, conteniendo `sub`, `moodle_user_id`, `is_teacher` y la lista de cursos autorizados (`allowed_courses`).
- Genera un **Refresh Token** criptográfico (`secrets.token_urlsafe(32)`), guarda su hash en la base de datos y lo devuelve en una cookie `HttpOnly` con flag de seguridad dinámico (`secure=True` en HTTPS de producción) y política `SameSite=Lax`.

8.2.2. Renovación y cierre de sesión: `POST /v1/refresh` y `POST /v1/logout`:
- Rotación estricta de refresh tokens: al refrescar, el token usado se invalida y se genera uno nuevo. Si un token ya revocado intenta usarse de nuevo, se detecta reutilización indebida y se anulan todas las sesiones activas del usuario.
- En caso de que el usuario no tenga cursos asignados, `/refresh` no devuelve un error 403 bloqueante, sino una lista vacía para permitirle ver la pantalla informativa de bienvenida.

8.2.3. Control de acceso en `src/metrics-api/metrics_api/auth.py`:
- `verify_token`: Decodifica y valida la firma y expiración del JWT en cada petición.
- `verificar_permisos(curso_id)`: Comprueba que el `curso_id` solicitado esté presente en el array `allowed_courses` del token JWT, impidiendo que un profesor o alumno acceda a métricas de asignaturas ajenas.

### 8.3 Métricas, conceptos y discrepancias

Implementamos los endpoints de consulta:
- `GET /v1/metrics/cursos/{curso_id}`: Resumen cuantitativo de interacciones, percentiles (p25, p50, p75, p90) y recuento de alumnos activos.
- `GET /v1/metrics/cursos/{curso_id}/estudiantes`: Listado de estudiantes del curso con número de interacciones, última actividad y estado de sincronización de su repositorio.
- `GET /v1/metrics/cursos/{curso_id}/estudiantes/{alumno_id}`: Detalle temporal de la actividad del alumno y conceptos más consultados.
- `GET /v1/metrics/cursos/{curso_id}/discrepancias`: Listado de incongruencias detectadas por la auditoría entre Git y la base de datos.
- `POST /v1/metrics/cursos/{curso_id}/sync`: Disparador manual para que el profesor pueda solicitar la reconciliación inmediata del repositorio de uno o todos los estudiantes.

### 8.4 Rúbricas y Agente Evaluador con IA

8.4.1. `src/metrics-api/metrics_api/agent.py`:
Agente que analiza el rendimiento de los alumnos usando modelos de lenguaje (Google Gemini / OpenAI):
- Extrae el historial de interacciones del estudiante en la asignatura.
- Aplica los criterios pedagógicos definidos en la rúbrica del curso.
- Genera observaciones formativas estructuradas por criterio (`nombre` y `observacion`), indicando si el alumno demuestra comprensión o requiere refuerzo, sin emitir calificaciones numéricas sesgadas.

### 8.5 Declaramos metrics-api en docker-compose.yml

```yaml
services:
  metrics-api:
    image: moodle-matrix-dev-mapeo-api
    container_name: ${METRICS_API_NOMBRE_CONTENEDOR}
    depends_on:
      mapeo-api:
        condition: service_healthy
    command: ["sh", "-c", "pip install -e . && alembic upgrade head && uvicorn metrics_api.main:app --host 0.0.0.0 --port ${PORT_METRICS_API} --proxy-headers --root-path \"${METRICS_API_ROOT_PATH:-}\""]
    volumes:
      - ./src/metrics-api:/app
      - ./config:/config
      - ./src/shared:/shared-pkg:ro
    ports:
      - "${PORT_METRICS_API_HOST}:${PORT_METRICS_API}"
    environment:
      - DATABASE_URL=${DATABASE_URL}
      - JWT_SECRET_KEY=${JWT_SECRET_KEY}
      - MAPEO_API_URL=${MAPEO_API_URL}
      - MAPEO_API_TOKEN=${MAPEO_API_TOKEN}
      - MOODLE_AUTH_URL=${MOODLE_AUTH_URL}
      - PII_SECRET_KEY=${PII_SECRET_KEY}
      - GEMINI_API_KEY=${GEMINI_API_KEY}
    networks:
      - default
      - bdc-net
```

---

## 9. metrics-worker

`metrics-worker` es el proceso de auditoría y reconciliación en segundo plano que vigila la integridad de los datos.

### 9.1 Reconciliación continua Git vs BD

9.1.1. Arquitectura de `src/metrics-worker/metrics_worker/worker.py`:
- Se ejecuta como un demonio asíncrono en bucle continuo (`asyncio.sleep`).
- Para cada alumno y curso registrado en `mapeo-api`:
  1. Inspecciona los commits de la rama por defecto del repositorio Git del alumno.
  2. Compara cada `commit_sha` contra los registrados en `eventos_sync`.
  3. Si encuentra un commit no firmado por la plataforma o con discrepancias en los archivos de log, inserta automáticamente una entrada en `discrepancias_auditoria`.
  4. Actualiza la tabla `auditoria_estado` con la marca de tiempo de la última revisión exitosa.

9.1.2. Módulo de carga histórica: `src/metrics-worker/metrics_worker/backfill.py`:
Permite procesar repositorios que ya contenían interacción histórica previa al despliegue del sistema para reconstruir la base de datos de métricas.

9.1.3. Declaramos `metrics-worker` en `docker-compose.yml`:
```yaml
services:
  metrics-worker:
    image: moodle-matrix-dev-mapeo-api
    container_name: ${METRICS_WORKER_NOMBRE_CONTENEDOR}
    depends_on:
      mapeo-api:
        condition: service_healthy
    command: ["sh", "-c", "export PYTHONPATH=/shared-pkg && pip install -e /metrics-api && pip install -e . && python -m metrics_worker.worker"]
    volumes:
      - ./src/metrics-worker:/app
      - ./src/metrics-api:/metrics-api
      - ./src/shared:/shared-pkg
    environment:
      - DATABASE_URL=${DATABASE_URL}
      - GITHUB_TOKEN=${GITHUB_PAT}
      - MAPEO_API_URL=${MAPEO_API_URL}
      - MAPEO_API_TOKEN=${MAPEO_API_TOKEN}
    networks:
      - default
      - bdc-net
```

---

## 10. frontend

El frontend es la interfaz web del profesorado desarrollada en **React 19, TypeScript y Vite**.

### 10.1 Estructura del proyecto y configuración de Vite

10.1.1. Carpetas en `src/frontend/`:
```text
src/frontend/
├── src/
│   ├── components/      # AuthGuard, CourseDashboard, StudentProfile, TeacherHome, RubricEditor, Login, Layout
│   ├── context/         # AuthContext.tsx (estado global de autenticación)
│   ├── lib/             # api.ts (interfaces TypeScript) y apiClient.ts (fetch configurado)
│   ├── App.tsx          # Definición de rutas con React Router
│   └── main.tsx         # Punto de entrada de React
├── package.json         # Dependencias (react, recharts, lucide-react, jwt-decode)
└── vite.config.ts       # Configuración de compilación, proxies y HMR
```

10.1.2. Configuración en `src/frontend/vite.config.ts`:
- Proxy reverso interno: Redirige las llamadas que empiezan por `VITE_API_BASE_URL` (`/api`) hacia el contenedor de `metrics-api` (`http://metrics-api:8002`).
- Prevención de bucles de recarga: Desactiva automáticamente el Hot Module Replacement (HMR) mediante WebSocket cuando `ENVIRONMENT=production` o `VITE_DISABLE_HMR=true`, evitando que el navegador recargue la página en bucle si el proxy inverso no transporta WebSockets.

### 10.2 Contexto de Autenticación y Guardias de Ruta

10.2.1. `src/frontend/src/context/AuthContext.tsx`:
- Mantiene el token JWT exclusivamente en memoria (evitando ataques XSS en `localStorage`).
- Al arrancar la aplicación, intenta un refresco automático silencioso contra `POST /refresh` utilizando la cookie segura `HttpOnly`.
- Monitoriza la fecha de expiración del token (`user.exp`). Para evitar desconexiones bruscas por desfase horario entre cliente y servidor, programa la renovación 1 minuto antes de expirar con un margen mínimo seguro de 15 segundos.
- Si una petición recibe un código 401 en cualquier vista, preserva la ruta actual en `sessionStorage.returnPath` para que tras identificarse de nuevo regrese exactamente a la misma pantalla.

10.2.2. `src/frontend/src/components/AuthGuard.tsx`:
- `AuthGuard`: Redirige a `/login` si el usuario no tiene una sesión activa.
- `RoleGuard`: Verifica que el usuario tenga privilegios docentes (`user.is_teacher == true`) para entrar a las vistas de administración de cursos y edición de rúbricas.

### 10.3 Pantallas y componentes

- `Login.tsx`: Formulario de acceso con usuario y contraseña de Moodle.
- `TeacherHome.tsx`: Listado de "Mis Cursos" con accesos directos al panel de control de cada asignatura asignada.
- `CourseDashboard.tsx`: Panel principal de la asignatura con gráficos de barras (Recharts) de interacciones por tipo, percentiles de actividad, tabla de estudiantes con ordenación dinámica y botones para forzar la sincronización manual.
- `StudentProfile.tsx`: Ficha individual del alumno con buscador filtrado de preguntas y respuestas, gráfico de nube de conceptos y botón para solicitar la evaluación formativa del agente de IA.
- `RubricEditor.tsx`: Editor interactivo donde los profesores pueden definir criterios personalizados de evaluación o restaurar la rúbrica global por defecto.

10.3.1. Declaramos `frontend` en `docker-compose.yml`:
```yaml
services:
  frontend:
    image: node:20-alpine
    container_name: ${FRONTEND_NOMBRE_CONTENEDOR}
    command: ["sh", "-c", "npm install && npm run dev"]
    volumes:
      - ./src/frontend:/app
    working_dir: /app
    ports:
      - "${FRONTEND_PUERTO_HOST}:${FRONTEND_PUERTO_CONTENEDOR}"
    environment:
      - VITE_API_TARGET_URL=${VITE_API_TARGET_URL}
      - VITE_API_BASE_URL=${VITE_API_BASE_URL}
      - VITE_BASE_PATH=${VITE_BASE_PATH}
      - PORT=${FRONTEND_PUERTO_CONTENEDOR}
      - VITE_ALLOWED_HOSTS=${DOMAIN}
      - ENVIRONMENT=${ENVIRONMENT}
      - VITE_DISABLE_HMR=${VITE_DISABLE_HMR:-}
    networks:
      - default
      - bdc-net
```

---

## 11. backup

El servicio de copias de seguridad garantiza la resiliencia de la plataforma ante pérdidas de datos accidentales.

### 11.1 Imagen Docker y Cron

11.1.1. Creamos `src/backup/Dockerfile`:
Utiliza una imagen base ligera de Alpine Linux con los clientes de línea de comandos de PostgreSQL y Redis:
```dockerfile
FROM alpine:3.19

RUN apk add --no-cache postgresql16-client redis tar gzip bash

WORKDIR /scripts

# Programa la ejecución del script cada madrugada a las 03:00 am
RUN echo "0 3 * * * /scripts/backup.sh > /proc/1/fd/1 2>/proc/1/fd/2" > /etc/crontabs/root

CMD ["crond", "-f", "-l", "2"]
```

### 11.2 Script backup.sh y política de retención

11.2.1. Implementamos `scripts/backup.sh`:
1. **Volcado de PostgreSQL:** Ejecuta `pg_dump -Fc` para volcar de forma atómica y comprimida las bases de datos de `mapeo_db`, `metrics` y `synapse` en un archivo con marca de tiempo: `mapeo_YYYYMMDD_HHMMSS.dump`.
2. **Volcado de Redis:** Comprime el directorio AOF (`/redis_data/appendonlydir`) en un archivo `redis_YYYYMMDD_HHMMSS.tar.gz`.
3. **Política de retención inteligente (evita saturar el disco):**
   - **0 a 7 días:** Conserva todas las copias de seguridad de la última semana.
   - **7 a 30 días:** Conserva únicamente una copia semanal (aquellas generadas los domingos), eliminando las copias intermedias.
   - **Más de 30 días:** Elimina cualquier copia de seguridad con más de un mes de antigüedad.

11.2.2. Declaramos `backup` en `docker-compose.yml`:
```yaml
services:
  backup:
    build:
      context: ./src/backup
      dockerfile: Dockerfile
    container_name: ${BACKUP_NOMBRE_CONTENEDOR}
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
    volumes:
      - ./scripts:/scripts:ro
      - ./backups:/backups
      - redis_data:/redis_data:ro
    networks:
      - default
      - bdc-net
```

---

## 12. Orquestación: instalar.sh y limpiar.sh

Para que el despliegue del proyecto no requiera ejecutar decenas de comandos manuales propensos a errores humanos, creamos scripts de automatización en Bash.

### 12.1 Script principal: instalar.sh

`instalar.sh` es el orquestador principal del proyecto y ofrece los siguientes comandos:
- `./instalar.sh`: Realiza el despliegue completo de la infraestructura.
- `./instalar.sh --env=dev`: Despliegue en modo desarrollo local.
- `./instalar.sh --ollama`: Activa el perfil para modelos LLM locales con Ollama.
- `./instalar.sh docs (serve|check)`: Genera y valida la documentación de código Doxygen.
- `./instalar.sh test`: Ejecuta la suite de pruebas unitarias y de integración con `pytest`.

El flujo de ejecución de `./instalar.sh` realiza los siguientes pasos en orden:
1. **Validación de prerrequisitos:** Comprueba que Docker y Docker Compose estén instalados en el sistema.
2. **Generación del archivo `.env`:** Si no existe `.env`, lo copia desde `.env.example` y autogenera claves criptográficas seguras (`JWT_SECRET_KEY`, `PII_SECRET_KEY`, `SYNAPSE_REGISTRATION_SHARED_SECRET`, etc.).
3. **Configuración de Synapse y Element:** 
   - Copia `rest_auth_provider.py` al volumen de Synapse y ajusta sus permisos numéricos de usuario (`991:991`).
   - Sustituye las variables de entorno en `homeserver.yaml.example` generando `homeserver.yaml` con valores literales.
   - Genera `config.json` de Element a partir de `config.json.template`.
4. **Levantado de contenedores:** Ejecuta `docker compose up -d --build`.
5. **Espera activa (Healthchecks):** Monitoriza el estado de los contenedores hasta que `moodle`, `mapeo-api`, `postgres` y `redis` estén en estado `healthy`.
6. **Configuración automática de Moodle:** Ejecuta `fix_wwwroot.php` para fijar dinámicamente el `wwwroot` de Moodle con soporte para HTTPS y proxy inverso.
7. **Empaquetado del plugin de Maubot:** Empaqueta `src/bot/llm-wiki-assistant-plugin/` en un fichero `.mbp` (Maubot Plugin) y lo sube automáticamente a la instancia de Maubot mediante su API REST.

### 12.2 Script de reseteo: limpiar.sh

`limpiar.sh` permite devolver el entorno a un estado completamente virgen cuando se necesita probar una instalación desde cero:
1. Detiene todos los contenedores y elimina volúmenes y redes: `docker compose down -v --rmi all --remove-orphans`.
2. Limpia la caché de construcción de Docker (`docker builder prune -f`).
3. Borra los archivos de bases de datos locales temporales (SQLite de Maubot en `src/bot/*.db` y logs de Synapse).

Con esta secuencia de desarrollo y automatización, el proyecto puede desplegarse en cualquier máquina o servidor con un único comando reproducible:

```bash
git clone <URL_REPOSITORIO>
cd llm-wiki-assistant-unificado
cp .env.example .env
./instalar.sh
```

