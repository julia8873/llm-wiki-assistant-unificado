# LLM Wiki Assistant (Ecosistema Unificado)

Este repositorio unifica el entorno completo de docencia y analítica, combinando las integraciones de **Moodle + Matrix + Git** con el sistema de trazabilidad y métricas de interacciones con IA.

---

## Estructura del Proyecto

El proyecto está diseñado mediante una arquitectura de microservicios. A continuación, se detalla qué hace cada directorio principal:

### Raíz
- **`docker-compose.yml`**: Archivo orquestador central que define y levanta todos los microservicios juntos (Bases de datos, APIs, Bots, Frontend, etc.).
- **`.env.example`**: Plantilla de variables de entorno donde se definen las contraseñas, tokens y configuración sensible de todo el ecosistema.
- **`instalar.sh`**: Script interactivo para facilitar la instalación y ejecución de herramientas de testeo/documentación.

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

Para desplegar el ecosistema desde cero, dispones de dos enfoques: usar el asistente automático o hacerlo manualmente.

### Opción A: Instalación Automatizada (Recomendado)
El script `./instalar.sh` es un orquestador que genera las plantillas, empaqueta el código y levanta el entorno paso a paso.

1. **Clonar y Entrar:**
   ```bash
   cd llm-wiki-assistant-unificado
   ```
2. **Generar archivos base automáticamente:**
   Ejecuta el orquestador sin argumentos:
   ```bash
   ./instalar.sh
   ```
   *El script detectará que te faltan los archivos de configuración, copiará automáticamente `.env` y `config/config.yaml` desde sus plantillas `.example`, y se detendrá avisándote de que debes rellenarlos.*
3. **Rellenar Secretos y Configuración:**
   - Abre el archivo `.env` recién creado y cambia todas las contraseñas marcadas como `CHANGE_ME`. Genera claves seguras para los secretos internos.
   - Abre `config/config.yaml`. Define tu `git.proveedor_activo` (ej. github) e introduce tu organización y PAT. **Importante para GitHub:** El token clásico debe tener marcado obligatoriamente el scope completo de **`repo`**.
   - En el mismo archivo, define tu `llm.proveedor_activo`.
4. **Levantar Infraestructura y Empaquetar:**
   Vuelve a ejecutar el orquestador:
   ```bash
   ./instalar.sh
   ```
   *Como ahora sí tienes los archivos configurados, el script levantará todos los contenedores Docker, empaquetará el bot (`.mbp`) y generará la documentación.*

---

### Opción B: Arranque Rápido Manual (Solo Docker)
Si prefieres hacerlo a mano, o solo quieres arrancar/reiniciar la red:
1. Copia los archivos manualmente:
   ```bash
   cp .env.example .env
   cp config/config.yaml.example config/config.yaml
   ```
2. Rellénalos con tus datos y secretos.
3. Levanta los contenedores usando el acceso directo:
   ```bash
   ./instalar.sh up
   ```
   *(Nota: `instalar.sh up` lee tu `config.yaml`, genera las variables finales y ejecuta `docker compose up -d` por ti. No genera la documentación ni empaqueta el bot. Si usas esta opción, deberás generar el bot luego con `./instalar.sh bot package`).*

---

### Paso 5: Operaciones Post-Instalación
Una vez estén los contenedores corriendo (puedes verificarlo con `docker ps`), necesitas enlazar el bot:

1. **Token de Matrix:** Entra a la interfaz de chat (Element) en `http://localhost:8081`, inicia sesión con el usuario `admin` y la contraseña de Synapse. Ve a *Ajustes -> Ayuda e información -> Avanzado* y copia tu **Token de Acceso**. Pégalo en tu archivo `.env` en la variable `MATRIX_ACCESS_TOKEN`.
2. **Reinicia Moodle:** Como Moodle necesita ese token, aplica los cambios reiniciándolo:
   ```bash
   docker compose restart moodle
   ```
3. **Configurar el Bot (Maubot):**
   - *Nota:* Si usaste la "Opción B" en el Paso 4, primero debes compilar el bot ejecutando `./instalar.sh bot package` para obtener el archivo `.mbp`. Si usaste la "Opción A", ya lo tienes listo.
   - Accede a la interfaz de administración en `http://localhost:29317/_matrix/maubot/` (usuario `admin`, contraseña la de tu `.env`).
   - Sube el plugin del bot (empaquetado como `.mbp`) en la pestaña **Plugins**, este se encontrará en: llm-wiki-assitant-unificado/src/bot/llm-wiki-assitant-plugin/plugin.mbp.
   - Añade el cliente conectándolo a `http://synapse:8008` (usando el usuario `@llm_wiki_bot:localhost`).
   - Crea la instancia uniendo el Cliente y el Plugin.

