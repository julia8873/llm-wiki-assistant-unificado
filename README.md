# LLM Wiki Assistant

En este repositorio se conectan los servicios de Moodle, Matrix, Git, y una API para obtener métricas de las interacciones de los estudiantes con LLMs.

## Índice
- [Estructura del Proyecto](#estructura-del-proyecto)
  - [Raíz](#raíz)
  - [Directorios Globales](#directorios-globales)
  - [Código Fuente (`src/`)](#código-fuente-src)
- [Guía de Instalación Paso a Paso](#guía-de-instalación-paso-a-paso)
  - [Generación de Documentación (Doxygen)](#generación-de-documentación-doxygen)

---

## Estructura del Proyecto

### Raíz
- **`docker-compose.yml`**: Levanta todos los microservicios juntos (Bases de datos, APIs, Bots, Frontend, etc.).
- **`.env.example`**: Plantilla de variables de entorno donde se definen las contraseñas, tokens y configuración.
- **`instalar.sh`**: Script que ejecutará todo el proyecto desde cero, generando el entorno y documentación.

### Directorios Globales
- **`config/`**: Contiene la configuración del proyecto que no sea sensible (por ejemplo los enlaces y puertos de cada servicio).
- **`docs/`**: Documentación del proyecto.
- **`scripts/`**: Scripts auxiliares.
- **`tests/`**: Tests del proyecto

### Código Fuente (`src/`)
Contiene los distintos microservicios:

* **Servicios Core (Infraestructura Base)**
  * **`moodle/`**: Código y configuración de Moodle, incluyendo el plugin personalizado (`block_bdc`).
  * **`matrix/`**: Configuración de Synapse (servidor Matrix) y Element (cliente web de chat).
  * **`bot/`**: Código fuente de *Maubot* (el bot de chat de Matrix) y de los *sync-workers* encargados de sincronizar en segundo plano el material con GitHub.
  * **`api/` (mapeo-api)**: API para el mapeo de los usuarios y sus gits (Alumno <-> Git <-> Matrix).
  * **`shared/`**: Paquetes y librerías de Python compartidas entre múltiples servicios para no repetir código.
  * **`backup/`**: Microservicio con un Cron que realiza copias de seguridad de las bases de datos.

* **Servicios de Trazabilidad (Analítica y Métricas)**
  * **`metrics-api/`**: API para manejar las interacciones de los alumnos con los LLMs.
  * **`metrics-worker/`**: Proceso en segundo plano para evitar discrepancias de la base de datos con git.
  * **`frontend/`**: Dashboard para que los profesores consulten las métricas de los alumnos.

---

## Guía de Instalación Paso a Paso

1. **Clonar y Entrar al Repositorio:**
   ```bash
   cd llm-wiki-assistant-unificado
   ```

2. **Preparar la Configuración:**
   Copia las plantillas de configuración a sus respectivos archivos finales:
   ```bash
   cp .env.example .env
   cp config/config.yaml.example config/config.yaml
   ```

3. **Configurar Variables de Entorno (`.env`) y Configuración Global (`config.yaml`):**
   - Abre el archivo `.env` recién creado y rellena los valores marcados como `[CAMBIAR]`.
   - **Token de GitHub:** El PAT clásico de GitHub debe tener el scope **`repo`** completo. Ponlo en `GITHUB_PAT`.
   - Abre `config/config.yaml` y define tu proveedor Git activo (`git.proveedor_activo`, ej. `github`).
   - **Si usas proxy inverso:** ajusta `DOMAIN`, `MAUBOT_PUBLIC_URL`, `FRONTEND_URL` y `MOODLE_EXTERNAL_URL` con el hostname público (sin puerto). Consulta los comentarios del `.env` para cada variable.

   > **Nota:** Las URLs internas de Element (`config.json`) y Maubot (`config.yaml`) se actualizan automáticamente al ejecutar `./instalar.sh`. No es necesario editarlas a mano.

4. **Configurar el Bot (Maubot):**
   - Accede a la interfaz de administración de Maubot en `http://localhost:29317/_matrix/maubot/` (o el `MAUBOT_PUBLIC_URL` que hayas configurado). Usuario `admin`, contraseña `MAUBOT_ADMIN_PASSWORD` del `.env`.
   - Sube el plugin del bot (empaquetado como `.mbp`) en la pestaña **Plugins**. El plugin compilado se encuentra en `src/bot/llm-wiki-assistant-plugin/plugin.mbp`.
   - Añade el cliente conectándolo a la URL interna de Synapse (`http://synapse:8008`) usando el usuario `@llm_wiki_bot:<DOMAIN>` (el valor de `MATRIX_BOT_USER` en tu `.env`). El **access token del bot** se puede obtener del `.env` tras ejecutar `./instalar.sh`.
   - Crea la instancia uniendo el Cliente y el Plugin.

---

### Generación de Documentación (Doxygen)

La documentación se puede generar con el siguiente comando:

```bash
./instalar.sh docs serve
```
