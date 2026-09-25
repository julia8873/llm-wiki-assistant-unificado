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
   Copia la plantilla de configuración:
   ```bash
   cp .env.example .env
   ```

3. **Configurar Variables de Entorno (`.env`):**
   - Abre el archivo `.env` recién creado y cambia todas las contraseñas y valores sensibles (marcados como `CHANGE_ME`).
      - **Importante para GitHub:** El token de acceso personal (PAT) clásico debe tener marcado obligatoriamente el scope completo de **`repo`**. Este token se coloca en la variable `GITHUB_PAT`.

  Si estás detrás de un proxy inverso, deberás revisar que la URL base de moodle y element corresponde al host:puerto o host/path según tengas configurado tu proxy.

  En Moodle se puede cambiar entrando en el contenedor y modificando la variable CFG->wwwroot dentro de /bitnami/moodel/config.php . En Element hay que cambiar el base_url dentro del archivo src/matrix/element/config.json

4. **Añadir tu usuario para poder ejecutar los scripts**
   ```bash
   sudo usermod -aG docker $USER
   newgrp docker
   # y ya podrás ejecutar
   ./instalar.sh
   ```
   
5. **Levantar la Infraestructura:**
   Ejecuta Docker Compose para construir y levantar todos los microservicios:
   ```bash
   docker compose up -d --build
   ```
6. **Configurar el Token de Matrix:** 
   - Entra en `http://localhost:8081`.
   - Inicia sesión con el usuario `admin` y la contraseña de Synapse configurada en tu `.env` (por defecto, `adminpass123_changeme`).
   - Ve a *Ajustes -> Ayuda e información -> Avanzado* y copia tu **Token de Acceso**.
   - Pégalo en tu archivo `.env` en la variable `MATRIX_ACCESS_TOKEN`.

7. **Reiniciar Servicios Afectados:** 
   Como Moodle necesita ese token para su configuración, aplica los cambios reiniciando su contenedor:
   ```bash
   docker compose restart moodle
   ```

8. **Configurar el Bot (Maubot):**
   - Accede a la interfaz de administración de Maubot en `http://localhost:29317/_matrix/maubot/` (usuario `admin`, y la contraseña de Maubot configurada en tu `.env`, por defecto `maubotpass_changeme`).
   - Sube el plugin del bot (empaquetado como `.mbp`) en la pestaña **Plugins**. El plugin compilado debería encontrarse en `src/bot/llm-wiki-assitant-plugin/plugin.mbp`.
   - Añade el cliente conectándolo a `http://synapse:8008` (usando el usuario `@llm_wiki_bot:localhost`). El **access bot token** se puede obtener al final del `.env` (generado tras ejecutar `./instalar.sh`).
   - Crea la instancia uniendo el Cliente y el Plugin.

---

### Generación de Documentación (Doxygen)

La documentación se puede generar con el siguiente comando:

```bash
./instalar.sh docs serve
```
