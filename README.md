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
   
   #### Configuración para Proxy Inverso (Producción)
   Variables a cambiar si se usa proxy inverso:

   * **`DOMAIN`**: Tu dominio base (ej. `mi-dominio.com`).
   * **`MOODLE_REVERSEPROXY_ENABLED`**: Cámbialo a `yes` para que Moodle sepa que está detrás de un proxy y genere bien las redirecciones.
   * **`MOODLE_EXTERNAL_URL`**: La URL pública de Moodle. Ej: `https://${DOMAIN}` (sin puerto).
   * **`ELEMENT_URL_BASE`**: La ruta pública donde vas a servir el cliente de chat Element. Ej: `https://${DOMAIN}/element` o `https://element.${DOMAIN}`.
   * **`MAUBOT_PUBLIC_URL`**: La URL pública para el panel web del bot. Ej: `https://${DOMAIN}/maubot` o `https://maubot.${DOMAIN}`.
   * **`FRONTEND_URL`**: La URL pública del dashboard de métricas de trazabilidad. Ej: `https://${DOMAIN}/trazabilidad` o `https://trazabilidad.${DOMAIN}`.
   * **`VITE_ALLOWED_HOSTS`**: Si el dashboard (Frontend) se sirve bajo un nombre de dominio concreto, añádelo aquí (ej. `trazabilidad.mi-dominio.com`) para que el servidor permita la conexión.
   * **`VITE_HMR_PORT`**: Descomenta y ajusta esta variable si usas Vite con un puerto público diferente al interno (ej. `443` para HTTPS).

   > **Nota:** Las URLs internas de Element (`config.json`) y Maubot (`config.yaml`) se actualizan automáticamente al ejecutar `./instalar.sh`. No es necesario editarlas a mano.

4. **Configurar y levantar los servicios:**
   Ejecuta el script de instalación principal:
   ```bash
   ./instalar.sh
   ```
   > **Diferencia entre `./instalar.sh` y `./instalar.sh up`:**
   > - `./instalar.sh` (sin argumentos) ejecuta la instalación completa: genera secretos en el `.env`, inyecta variables en las plantillas de configuración, levanta Docker Compose, auto-registra a los usuarios en Matrix, extrae los tokens necesarios y finalmente empaqueta el plugin de Maubot.
   > - `./instalar.sh up` ejecuta todo lo anterior, **excepto** la fase de empaquetado del plugin del bot. Usa `up` si solo quieres levantar la infraestructura sin recompilar el `.mbp`.

5. **Configurar el Bot (Maubot):**
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

---

## Uso del Asistente (Comandos)

El bot de Matrix ofrece varios comandos para interactuar con tu base de conocimiento personal (repositorio). Escribe `!ayuda` o `!comandos` en el chat para ver la lista completa.

### Ingesta de Documentos
Hay dos formas de proporcionar apuntes al bot para que extraiga sus conceptos usando Inteligencia Artificial:

1. **Subida por chat (Recomendado):**
   Arrastra y suelta tu archivo PDF o documento de texto en la ventana del chat. El bot lo detectará automáticamente y te preguntará si quieres procesarlo (respondiendo `si` o `ocr`). Él mismo se encargará de subir los conceptos procesados a tu repositorio.

2. **Subida manual por Git (`!ingestar`):**
   Si prefieres subir los archivos manualmente a tu repositorio, puedes hacer un commit de tu documento dentro de la carpeta `raw/`. Tras hacer el push, ve al chat de Matrix y escribe:
   ```text
   !ingestar nombre_del_archivo.pdf
   ```
   El bot descargará el documento directamente desde GitHub y comenzará el proceso de extracción, actualizando el repositorio con los nuevos conceptos extraídos. Añade la palabra `ocr` al final si el documento contiene imágenes o escaneos.

---

## Resolución de Problemas

### Synapse no inicia por falta de permisos
Si el contenedor de Matrix (`synapse`) se reinicia o falla al intentar escribir en su base de datos local y/o subir archivos, es probable que no tenga permisos sobre la carpeta montada como volumen.

Se le puede dar permisos al usuario de Synapse (cuyo UID es `991`) en el directorio `synapse-data`:
```bash
sudo chown -R 991:991 ./src/matrix/synapse-data
```
