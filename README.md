# LLM Wiki Assistant (Ecosistema Unificado)

Este repositorio unifica el entorno completo de docencia y analítica, combinando las integraciones de **Moodle + Matrix + Git** con el sistema de trazabilidad y métricas de interacciones con IA.

---

## Estructura del Proyecto

El proyecto está diseñado mediante una arquitectura de microservicios. A continuación, se detalla qué hace cada directorio principal:

### Raíz
- **`docker-compose.yml`**: Archivo orquestador central que define y levanta todos los microservicios juntos (Bases de datos, APIs, Bots, Frontend, etc.).
- **`.env.example`**: Plantilla de variables de entorno donde se definen las contraseñas, tokens y configuración sensible de todo el ecosistema.
- **`instalar.sh`**: Script interactivo para la ejecución de herramientas de testeo, generación de documentación y operaciones auxiliares.

### Directorios Globales
- **`config/`**: Contiene `config.yaml`, que funciona como la única fuente de verdad para la configuración no sensible (proveedores LLM a usar, configuración del repositorio Git, etc.).
- **`docs/`**: Documentación técnica detallada y diagramas.
- **`scripts/`**: Scripts auxiliares (como herramientas de volcado de bases de datos).
- **`tests/`**: Batería de pruebas automatizadas consolidadas de todo el sistema.

### Código Fuente (`src/`)
Contiene los distintos microservicios:

* **Servicios Core (Infraestructura Base)**
  * **`moodle/`**: Código y configuración de Moodle, incluyendo el plugin personalizado (`block_bdc`) que intercepta inicios de sesión para sincronizar usuarios.
  * **`matrix/`**: Configuración de Synapse (servidor Matrix) y Element (cliente web de chat).
  * **`bot/`**: Código fuente de *Maubot* (el bot de chat de Matrix) y de los *sync-workers* encargados de sincronizar en segundo plano el material con GitHub.
  * **`api/` (mapeo-api)**: API puente encargada de mantener el mapeo central de usuarios (Alumno <-> Git <-> Matrix).
  * **`shared/`**: Paquetes y librerías de Python compartidas entre múltiples servicios para no repetir código.
  * **`backup/`**: Microservicio con un Cron que realiza copias de seguridad de las bases de datos.

* **Servicios de Trazabilidad (Analítica y Métricas)**
  * **`metrics-api/`**: API dedicada a recopilar, consolidar y exponer los eventos de interacción y el catálogo pedagógico de IA de los estudiantes.
  * **`metrics-worker/`**: Proceso en segundo plano que audita los repositorios Git en busca de discrepancias o interacciones nuevas para ingresarlas a la BD.
  * **`frontend/`**: Dashboard visual hecho en React/Vite para que los profesores consulten las métricas de los alumnos.

---

## Guía de Instalación Paso a Paso

Para desplegar el ecosistema desde cero, debes configurar tus variables de entorno y levantar los contenedores mediante Docker Compose.

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
   - Abre el archivo `.env` recién creado y cambia todas las contraseñas y valores sensibles (marcados como `CHANGE_ME`).
      - **Importante para GitHub:** El token de acceso personal (PAT) clásico debe tener marcado obligatoriamente el scope completo de **`repo`**. Este token se coloca en la variable `GITHUB_PAT`.
      - Define tu proveedor de LLM (`llm.proveedor_activo`).

   - Abre `config/config.yaml` y define tu proveedor Git activo (`git.proveedor_activo`, ej. `github`) e introduce tu organización.
   

4. **Levantar la Infraestructura:**
   Ejecuta Docker Compose para construir y levantar todos los microservicios:
   ```bash
   docker compose up -d --build
   ```
   *(Nota: Puedes verificar que los contenedores están corriendo correctamente con `docker ps`).*

---

### Operaciones Post-Instalación

Una vez estén los contenedores corriendo, es necesario enlazar los componentes:

1. **Obtener el Token de Matrix:** 
   - Entra a la interfaz de chat (Element) en `http://localhost:8081`.
   - Inicia sesión con el usuario `admin` y la contraseña de Synapse configurada en tu `.env`.
   - Ve a *Ajustes -> Ayuda e información -> Avanzado* y copia tu **Token de Acceso**.
   - Pégalo en tu archivo `.env` en la variable `MATRIX_ACCESS_TOKEN`.

2. **Reiniciar Servicios Afectados:** 
   Como Moodle necesita ese token para su configuración, aplica los cambios reiniciando su contenedor:
   ```bash
   docker compose restart moodle
   ```

3. **Configurar el Bot (Maubot):**
   - Accede a la interfaz de administración de Maubot en `http://localhost:29317/_matrix/maubot/` (usuario `admin`, y la contraseña definida en tu `.env`).
   - Sube el plugin del bot (empaquetado como `.mbp`) en la pestaña **Plugins**. El plugin compilado debería encontrarse en `src/bot/llm-wiki-assitant-plugin/plugin.mbp`.
   - Añade el cliente conectándolo a `http://synapse:8008` (usando el usuario `@llm_wiki_bot:localhost`). El access token del bot se puede generar desde Synapse o encontrarlo según tu configuración.
   - Crea la instancia uniendo el Cliente y el Plugin.

