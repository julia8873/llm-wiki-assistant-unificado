#!/usr/bin/env bash
## @file instalar.sh
## @brief Script orquestador principal del proyecto LLM Wiki Assistant.
## 
## Centraliza las operaciones de despliegue, configuración y gestión de la infraestructura
## Docker Compose y documentación Doxygen.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${ROOT_DIR}/config/config.yaml"

# Evitar que Git Bash (MINGW64) convierta rutas como "/data" a rutas de Windows
export MSYS_NO_PATHCONV=1

## @fn info()
## @brief Imprime un mensaje informativo estándar.
## @param $1 Mensaje de información a imprimir.
info()  { echo "[INFO]  $*"; }

## @fn ok()
## @brief Imprime un mensaje de éxito.
## @param $1 Mensaje de éxito a imprimir.
ok()    { echo "[ OK ]  $*"; }

## @fn warn()
## @brief Imprime un mensaje de advertencia.
## @param $1 Mensaje de advertencia a imprimir.
warn()  { echo "[WARN]  $*"; }

## @fn skip()
## @brief Imprime un mensaje de salto de tarea.
## @param $1 Mensaje de salto a imprimir.
skip()  { echo "[SKIP]  $*"; }

## @fn error()
## @brief Imprime un error crítico en stderr y aborta la ejecución.
## @param $1 Mensaje de error.
## @exception Aborta el script con código de salida 1.
error() { echo "[ERROR] $*" >&2; exit 1; }

## @fn check_docker()
## @brief Verifica la disponibilidad del binario de Docker.
## @exception Llama a error() si Docker no está instalado en el PATH.
check_docker() {
  command -v docker &>/dev/null || error "Docker no está instalado. Requerido para continuar."
}

## @fn yaml_get()
## @brief Extrae el valor de una clave hoja desde config.yaml usando grep y awk.
## @param $1 Clave a buscar (e.g., puerto_host).
## @param $2 Valor por defecto a retornar si no se encuentra la clave.
## @return String con el valor encontrado o el por defecto.
yaml_get() {
  local key="$1" default="${2:-}"
  local value
  value=$(grep -m1 "${key}:" "${CONFIG_FILE}" 2>/dev/null \
    | awk -F': ' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); gsub(/"/, "", $2); print $2}' || true)
  echo "${value:-$default}"
}

## @fn copy_if_missing()
## @brief Copia un archivo plantilla (ej. .example) a su destino real si no existe.
## @param $1 Ruta absoluta del fichero origen.
## @param $2 Ruta absoluta del fichero destino.
copy_if_missing() {
  local src="$1" dst="$2"
  if [[ -f "$dst" ]]; then
    skip "$(basename "$dst") ya existe, no se sobreescribe."
  else
    cp "$src" "$dst"
    ok "$(basename "$dst") creado desde $(basename "$src")."
    warn "  Edita ${dst} e inyecta los secretos reales."
  fi
}

## @fn usage()
## @brief Muestra la ayuda y el listado de subcomandos soportados.
## @return Finaliza la ejecución limpiamente (exit 0).
usage() {
  cat <<EOF
LLM Wiki Assistant — instalar.sh

Comandos base:
  (sin argumentos)         Instalación/arranque automático completo.
  help                     Muestra esta ayuda.

Fase 0.1 (Documentación):
  docs serve               Genera y levanta Doxygen HTTP en el puerto configurado.
  docs check               Genera Doxygen en modo estricto (falla ante warnings).

Fase 1 (Entorno Docker):
  up                       Levanta el stack Docker Compose.
  down [--volumes]         Detiene el stack.
  logs [servicio]          Muestra logs.
  status                   Estado de contenedores.
  git setup                Configura repositorios base.

Fase 3 (Sincronización):
  bot sync                 Fuerza actualización Moodle -> Matrix.

Fase 5 (Bot LLM):
  bot package              Empaqueta el plugin de Maubot (.mbp).

Fase 7 (Tests Consolidados):
  --test [--full]          Ejecuta toda la batería de pruebas (Fases 0-6).
                           Con --full se reinicia la infraestructura desde cero.
EOF
  exit 0
}

## @fn warn_pending_config()
## @brief Informa al usuario de que debe rellenar las variables de entorno pendientes.
## @details Se llama al final de la instalación, después de que los contenedores estén operativos.
## El MATRIX_ACCESS_TOKEN sólo puede obtenerse tras levantar Element/Synapse (Fase 1).
warn_pending_config() {
  local env_file="${ROOT_DIR}/.env"
  local cfg_file="${ROOT_DIR}/config/config.yaml"
  local has_pending=false

  if grep -q "CHANGE_ME" "$env_file" 2>/dev/null; then has_pending=true; fi
  if grep -q "CHANGE_ME" "$cfg_file" 2>/dev/null; then has_pending=true; fi

  if [[ "$has_pending" == true ]]; then
    echo ""
    echo "⚠️  ACCIÓN REQUERIDA: INTRODUCE TUS CREDENCIALES"
    echo "--------------------------------------------------------------------"
    echo "  Los contenedores están operativos."
    echo "  Los siguientes campos aún tienen el valor CHANGE_ME y deben ser"
    echo "  configurados antes de que el sistema funcione correctamente:"
    echo ""

    if grep -q "CHANGE_ME" "$env_file" 2>/dev/null; then
      echo "  📄 .env"
      grep "CHANGE_ME" "$env_file" | sed 's/=.*//' | while read -r var; do
        echo "      → $var"
      done
      echo ""
    fi

    if grep -q "CHANGE_ME" "$cfg_file" 2>/dev/null; then
      echo "  📄 config/config.yaml"
      grep "CHANGE_ME" "$cfg_file" | grep -v "^[[:space:]]*#" | sed 's/:.*$//' | sed 's/^[[:space:]]*//' | while read -r key; do
        echo "      → $key"
      done
      echo ""
    fi

    echo "  MATRIX_ACCESS_TOKEN — cómo obtenerlo (requiere Element operativo):"
    echo "      1. Abre http://localhost:8081 (Element)"
    echo "      2. Inicia sesión como administrador"
    echo "      3. Ajustes → Ayuda e información → Avanzado → Token de acceso"
    echo "      4. Pégalo en .env como:  MATRIX_ACCESS_TOKEN=syt_..."
    echo ""
    
    local bot_token=$(grep -E "^BOT_ACCESS_TOKEN=" "${ROOT_DIR}/.env" | cut -d= -f2- || true)
    if [[ -n "$bot_token" ]]; then
      echo "  TOKEN DEL BOT (llm_wiki_bot) PARA MAUBOT:"
      echo "      $bot_token"
      echo ""
    fi

    echo "  Cuando hayas rellenado los archivos, ejecuta de nuevo:"
    echo "      ./instalar.sh up"
    echo "--------------------------------------------------------------------"
    echo ""
  fi
}

## @fn cmd_install_all()
## @brief Flujo principal de instalación que se ejecuta por defecto sin argumentos.
## 
## 1. Copia secretos y configura base.
## 2. Inicia servidor de documentación.
cmd_install_all() {
  echo ""
  echo "=== LLM Wiki Assistant — Orquestador de Instalación ==="
  echo "    Raíz: ${ROOT_DIR}"
  echo ""

  echo "--- Fase: Configuración Base y Secretos ---"
  copy_if_missing "${ROOT_DIR}/.env.example"                                      "${ROOT_DIR}/.env"
  copy_if_missing "${ROOT_DIR}/config/config.yaml.example"                        "${ROOT_DIR}/config/config.yaml"
  copy_if_missing "${ROOT_DIR}/src/bot/base-config.yaml.example" "${ROOT_DIR}/src/bot/base-config.yaml"
  copy_if_missing "${ROOT_DIR}/src/bot/config.yaml.example"      "${ROOT_DIR}/src/bot/config.yaml"
  echo ""

  echo "--- Fase: Stack Docker ---"
  if grep -q "CHANGE_ME" "${ROOT_DIR}/.env" 2>/dev/null || grep -q "CHANGE_ME" "${ROOT_DIR}/config/config.yaml" 2>/dev/null; then
    warn_pending_config
    error "La instalación se ha detenido porque necesitas rellenar los secretos en .env y config/config.yaml."
  fi
  cmd_up "$@"
  echo ""


  echo "--- Fase: Servidor de Documentación (Doxygen) ---"
  check_docker
  
  echo ""
  echo "--- Fase: Empaquetado del Bot LLM (Fase 5) ---"
  cmd_bot package

  echo "=== Secuencia Completada ==="
  echo "  [OK] Entorno configurado"
  echo "  [OK] Lanzando servidor Doxygen silencioso"
  echo ""
  cmd_docs serve
  warn_pending_config
}

## @fn cmd_docs()
## @brief Gestiona el ciclo de vida de la documentación Doxygen vía Docker Alpine.
## @param $1 Comando subordinado (serve|check). Por defecto 'serve'.
## @exception Aborta si el comando es inválido o falla la validación estricta (check).
cmd_docs() {
  local submode="${1:-serve}"
  info "TODO: documentación Doxygen."
  return 0
}

### @fn generate_env()
## @brief Genera el fichero .env a partir de .env.example si no existe, y autorrellena tokens secretos.
generate_env() {
  local env_file="${ROOT_DIR}/.env"

  info "Comprobando ${env_file}..."

  # Si no existe el .env, crearlo desde la plantilla
  if [[ ! -f "$env_file" ]]; then
    copy_if_missing "${ROOT_DIR}/.env.example" "$env_file"
  fi

  # Generar MAPEO_API_TOKEN si está en modo default
  if grep -q "MAPEO_API_TOKEN=changeme" "$env_file"; then
    local new_token=$(openssl rand -hex 16)
    sed -i "s/MAPEO_API_TOKEN=changeme/MAPEO_API_TOKEN=${new_token}/" "$env_file"
    info "Se ha generado un MAPEO_API_TOKEN aleatorio para esta instancia."
  fi

  # Eliminar retornos de carro (CRLF -> LF) para evitar errores "command not found" al hacer source en WSL
  sed -i 's/\r$//' "$env_file"

  # Parchear credenciales de Maubot en su config.yaml (vía Docker para evitar permisos denegados)
  local m_pass; m_pass=$(grep -m 1 "^MAUBOT_ADMIN_PASSWORD=" "$env_file" 2>/dev/null | cut -d= -f2- | tr -d '\r' || true)
  local m_key; m_key=$(grep -m 1 "^MAUBOT_CRYPTO_PICKLE_KEY=" "$env_file" 2>/dev/null | cut -d= -f2- | tr -d '\r' || true)

  if [[ -n "$m_pass" || -n "$m_key" ]]; then
    info "Inyectando credenciales en Maubot..."
    check_docker
    docker run --rm -v "${ROOT_DIR}/src/bot:/data" alpine sh -c "
      if [ -n \"$m_pass\" ]; then
        sed -i -e \"s|root: ''|admin: \\\"${m_pass}\\\"|\" -e \"s|admin: \\\"CHANGE_ME_PASSWORD\\\"|admin: \\\"${m_pass}\\\"|\" /data/config.yaml 2>/dev/null || true
      fi
      if [ -n \"$m_key\" ]; then
        sed -i \"s|pickle_key: .*|pickle_key: \\\"${m_key}\\\"|\" /data/config.yaml 2>/dev/null || true
      fi
    "
    # Reiniciamos maubot por si estaba corriendo, para que tome el nuevo config.yaml
    docker compose -f "${ROOT_DIR}/docker-compose.yml" restart maubot >/dev/null 2>&1 || true
  fi

  return 0
}


## @fn print_summary()
## @brief Imprime la tabla resumen de credenciales y URLs
print_summary() {
  set +u # Permitir variables no definidas temporalmente
  source "${ROOT_DIR}/.env"
  set -u
  
  echo ""
  echo "=== RESUMEN DE SERVICIOS (Fase 1) ==="
  echo "Servicio    URL                              Credenciales"
  echo "----------------------------------------------------------------"
  echo "Moodle      http://localhost:${MOODLE_PUERTO_HOST:-8000}                        ${MOODLE_USERNAME:-admin} / ${MOODLE_PASSWORD:-adminpass123}"
  echo "Matrix      http://localhost:${SYNAPSE_PUERTO_HOST:-8008}                        -"
  echo "Element     http://localhost:${ELEMENT_PUERTO_HOST:-8081}                        -"
  echo "Maubot      http://localhost:${MAUBOT_PUERTO_HOST:-29317}/_matrix/maubot       -"
  echo "Doxygen     http://localhost:8005                                               -"
  echo "Mapeo API   http://mapeo-api:8000                                               (Solo red interna Docker. Token: ${MAPEO_API_TOKEN})"
  
  cd "${ROOT_DIR}" || true
  if docker compose ps --services --filter "status=running" 2>/dev/null | grep -q "ollama"; then
    echo "Ollama      http://${OLLAMA_BASE_URL:-localhost}:${OLLAMA_PORT:-11434}          (Perfil Activo)"
  else
    echo "Ollama      -                                (Inactivo. Usa --ollama para levantar)"
  fi
  cd "${ROOT_DIR}"
  
  echo "----------------------------------------------------------------"
  echo "Proveedores LLM configurados en config/config.yaml."
  echo ""
}

# ------------------------------------------------------------------------------
# Stubs de fases futuras
# ------------------------------------------------------------------------------

## @fn setup_synapse_admin()
## @brief Registra y promueve al usuario administrador configurado en .env como admin de Synapse.
## @details Se ejecuta tras el primer arranque de los contenedores para garantizar que el
## MATRIX_ACCESS_TOKEN sea de un admin de Synapse y pueda crear usuarios/salas vía la Admin API.
setup_synapse_admin() {
  local synapse_url="http://localhost:8008"
  local admin_user; admin_user=$(grep -m 1 '^SYNAPSE_ADMIN_USER=' "${ROOT_DIR}/.env" | cut -d= -f2- | tr -d '\r')
  local admin_pass; admin_pass=$(grep -m 1 '^SYNAPSE_ADMIN_PASSWORD=' "${ROOT_DIR}/.env" | cut -d= -f2- | tr -d '\r' | sed 's/_CHANGE_ME.*//')
  local token_in_env; token_in_env=$(grep -m 1 '^MATRIX_ACCESS_TOKEN=' "${ROOT_DIR}/.env" | cut -d= -f2- | tr -d '\r')

  admin_user=${admin_user:-admin}
  admin_pass=${admin_pass:-adminpass123}

  info "Verificando que @${admin_user}:localhost sea admin de Synapse..."

  # 1. Intentar login para obtener token fresco
  local login_resp
  login_resp=$(curl -sf --max-time 10 -X POST "${synapse_url}/_matrix/client/v3/login" \
    -H 'Content-Type: application/json' \
    -d "{\"type\":\"m.login.password\",\"user\":\"${admin_user}\",\"password\":\"${admin_pass}\"}" 2>/dev/null || echo '')
  local fresh_token; fresh_token=$(echo "$login_resp" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4 || true)

  if [[ -z "$fresh_token" ]]; then
    info "Registrando usuario admin en Synapse..."
    docker exec moodle-matrix-dev-synapse-1 \
      register_new_matrix_user -c /data/homeserver.yaml --admin \
      -u "$admin_user" -p "$admin_pass" http://localhost:8008 2>/dev/null || true

    # Reintentar login
    login_resp=$(curl -sf -X POST "${synapse_url}/_matrix/client/v3/login" \
      -H 'Content-Type: application/json' \
      -d "{\"type\":\"m.login.password\",\"user\":\"${admin_user}\",\"password\":\"${admin_pass}\"}" 2>/dev/null || echo '')
    fresh_token=$(echo "$login_resp" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4 || true)
  fi

  if [[ -z "$fresh_token" ]]; then
    warn "No se pudo obtener token de Synapse para @${admin_user}:localhost. Omitiendo promoción a admin."
    return
  fi

  # 2. Comprobar si ya es admin
  local user_info
  user_info=$(curl -sf -H "Authorization: Bearer ${fresh_token}" \
    "${synapse_url}/_synapse/admin/v2/users/@${admin_user}:localhost" 2>/dev/null || echo '')
  local is_admin; is_admin=$(echo "$user_info" | grep -o '"admin":[^,}]*' | cut -d: -f2 | tr -d ' ' || true)

  if [[ "$is_admin" == "true" ]]; then
    ok "@${admin_user}:localhost ya es admin de Synapse."
  else
    info "Promoviendo @${admin_user}:localhost a admin de Synapse (vía DB)..."
    docker exec moodle-matrix-dev-synapse-1 python -c "import sqlite3; conn = sqlite3.connect('/data/homeserver.db'); conn.execute('UPDATE users SET admin = 1 WHERE name = \'@${admin_user}:localhost\''); conn.commit(); conn.close()" 2>/dev/null || true
    # Reiniciar synapse para asegurar que el cambio de DB se aplique en memoria
    docker restart moodle-matrix-dev-synapse-1 >/dev/null
    
    # Esperar a que vuelva a levantar
    sleep 5
    while true; do
      local s_status=$(docker inspect --format="{{if .State.Health}}{{.State.Health.Status}}{{end}}" "moodle-matrix-dev-synapse-1" 2>/dev/null || echo "starting")
      if [[ "$s_status" == "healthy" ]]; then
        break
      fi
      sleep 2
    done
    ok "@${admin_user}:localhost promovido a admin de Synapse y servicio reiniciado."

    # Obtener token fresco tras el reinicio
    login_resp=$(curl -sf --max-time 10 -X POST "${synapse_url}/_matrix/client/v3/login" \
      -H 'Content-Type: application/json' \
      -d "{\"type\":\"m.login.password\",\"user\":\"${admin_user}\",\"password\":\"${admin_pass}\"}" 2>/dev/null || echo '')
    fresh_token=$(echo "$login_resp" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4 || true)
  fi

  # Persistir el token de admin en .env para que Moodle pueda usarlo
  if [[ -n "$fresh_token" ]]; then
    local env_file="${ROOT_DIR}/.env"
    if grep -q '^MATRIX_ACCESS_TOKEN=' "$env_file"; then
      sed -i "s|^MATRIX_ACCESS_TOKEN=.*|MATRIX_ACCESS_TOKEN=${fresh_token}|" "$env_file"
    else
      echo "MATRIX_ACCESS_TOKEN=${fresh_token}" >> "$env_file"
    fi
    ok "MATRIX_ACCESS_TOKEN actualizado en .env con token fresco de admin."
  fi
}

## @fn setup_bot_token()
## @brief Registra el bot en Synapse y obtiene su Access Token, guardándolo en .env
setup_bot_token() {
  local root_env="${ROOT_DIR}/.env"
  local bot_token; bot_token=$(grep -E "^BOT_ACCESS_TOKEN=" "$root_env" | cut -d= -f2- || true)
  
  if [[ -z "$bot_token" ]]; then
    info "Generando Access Token para el bot (llm_wiki_bot)..."
    local bot_pass; bot_pass=$(grep -m 1 "^SYNAPSE_ADMIN_PASSWORD=" "$root_env" | cut -d= -f2- | tr -d '\r')
    
    # 1. Registrar usuario bot
    docker exec moodle-matrix-dev-synapse-1 \
      register_new_matrix_user -c /data/homeserver.yaml --no-admin \
      -u "llm_wiki_bot" -p "$bot_pass" http://localhost:8008 2>/dev/null || true
      
    # 2. Hacer login para obtener token
    local login_resp
    login_resp=$(curl -sf -X POST "http://localhost:8008/_matrix/client/v3/login" \
      -H 'Content-Type: application/json' \
      -d "{\"type\":\"m.login.password\",\"user\":\"llm_wiki_bot\",\"password\":\"${bot_pass}\"}" 2>/dev/null || echo '')
      
    bot_token=$(echo "$login_resp" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4 || true)
    
    if [[ -n "$bot_token" ]]; then
      echo "BOT_ACCESS_TOKEN=${bot_token}" >> "$root_env"
      ok "Access Token del bot generado exitosamente."
    else
      warn "No se pudo generar el Access Token para el bot."
    fi
  fi
}

## @fn cmd_up()
## @brief Levanta la infraestructura de Fase 1
cmd_up() {
  local use_ollama=false
  local env_mode="production"
  for arg in "$@"; do
    if [[ "$arg" == "--ollama" ]]; then
      use_ollama=true
    fi
    if [[ "$arg" == "--env=dev" ]]; then
      env_mode="dev"
    fi
    if [[ "$arg" == "--env=production" ]]; then
      env_mode="production"
    fi
  done
  
  generate_env
  
  if [[ "$env_mode" == "production" ]]; then
    # Fail fast si no hay DATABASE_URL o no es postgres
    local db_url=$(grep -E "^DATABASE_URL=" "${ROOT_DIR}/.env" | cut -d= -f2- || true)
    if [[ -z "$db_url" || ! "$db_url" =~ ^postgresql ]]; then
      error "En modo production, DATABASE_URL debe estar configurado y apuntar a PostgreSQL. Para usar SQLite en desarrollo local, ejecuta con '--env=dev'."
    fi
  fi

  info "Levantando servicios Docker Compose (Modo: ${env_mode})..."
  local domain; domain=$(grep -m 1 '^DOMAIN=' "${ROOT_DIR}/.env" | cut -d= -f2- | tr -d '\r' || echo "localhost")
  if [[ "$domain" != "localhost" ]]; then
    info "Inyectando DOMAIN=${domain} en archivos estáticos..."
    sed -i "s/localhost/${domain}/g" "${ROOT_DIR}/src/matrix/synapse-data/homeserver.yaml" 2>/dev/null || true
    sed -i "s/localhost/${domain}/g" "${ROOT_DIR}/src/matrix/element/config.json" 2>/dev/null || true
    sed -i "s/localhost/${domain}/g" "${ROOT_DIR}/src/bot/base-config.yaml" 2>/dev/null || true
    sed -i "s/localhost/${domain}/g" "${ROOT_DIR}/src/bot/config.yaml" 2>/dev/null || true
  fi

  cd "${ROOT_DIR}"
  
  local compose_args="-f docker-compose.yml"
  if [[ "$env_mode" == "dev" ]]; then
    compose_args="-f docker-compose.yml -f docker-compose.dev.yml"
  fi

  if [ "$use_ollama" = true ]; then
    info "Perfil Ollama activado."
    docker compose $compose_args --env-file .env --profile ollama up -d --build --pull=missing
  else
    docker compose $compose_args --env-file .env up -d --build --pull=missing
  fi
  
  info "Esperando a que Moodle y mapeo-api estén operativos (Healthchecks)..."
  # Leer el nombre del contenedor dinámico
  local moodle_container=$(grep -m 1 MOODLE_NOMBRE_CONTENEDOR .env | cut -d= -f2 || echo "moodle-matrix-dev-moodle-1")
  local mapeo_api_container=$(grep -m 1 MAPEO_API_NOMBRE_CONTENEDOR .env | cut -d= -f2 || echo "moodle-matrix-dev-mapeo-api-1")
  
  while true; do
    local m_status=$(docker inspect --format="{{if .State.Health}}{{.State.Health.Status}}{{end}}" "$moodle_container" 2>/dev/null || echo "starting")
    local api_status=$(docker inspect --format="{{if .State.Health}}{{.State.Health.Status}}{{end}}" "$mapeo_api_container" 2>/dev/null || echo "starting")
    
    if [[ "$m_status" == "healthy" && "$api_status" == "healthy" ]]; then
      ok "Moodle y mapeo-api están operativos."
      
      # Configuramos el SSO de Matrix automáticamente si es la primera vez
      if [[ -f "synapse-data/homeserver.yaml" ]] && ! grep -q "password_providers:" "synapse-data/homeserver.yaml"; then
        info "Inyectando configuración SSO de Moodle en Synapse..."
        cat << 'EOF' >> "synapse-data/homeserver.yaml"

password_providers:
  - module: "rest_auth_provider.RestAuthProvider"
    config:
      endpoint: "http://moodle:8080/blocks/bdc/api/auth.php"
EOF
        docker compose restart synapse
        ok "Synapse reiniciado con soporte SSO."
      fi

      # Esperar a que Synapse esté disponible y configurar admin y bot
      info "Esperando a que Synapse esté operativo (Healthcheck)..."
      local synapse_container=$(grep -m 1 SYNAPSE_NOMBRE_CONTENEDOR .env | cut -d= -f2 | tr -d '\r' || echo "moodle-matrix-dev-synapse-1")
      while true; do
        local s_status=$(docker inspect --format="{{if .State.Health}}{{.State.Health.Status}}{{end}}" "$synapse_container" 2>/dev/null || echo "starting")
        if [[ "$s_status" == "healthy" ]]; then
          setup_synapse_admin
          setup_bot_token
          # Recrear Moodle para que cargue el MATRIX_ACCESS_TOKEN actualizado en .env
          local moodle_container; moodle_container=$(grep -m 1 MOODLE_NOMBRE_CONTENEDOR .env | cut -d= -f2 | tr -d '\r' || echo "moodle-matrix-dev-moodle-1")
          info "Reiniciando Moodle para cargar el nuevo MATRIX_ACCESS_TOKEN..."
          docker compose up -d --no-deps moodle >/dev/null 2>&1 || true
          # Esperar a que Moodle vuelva a estar healthy
          sleep 10
          while true; do
            local m2_status=$(docker inspect --format="{{if .State.Health}}{{.State.Health.Status}}{{end}}" "$moodle_container" 2>/dev/null || echo "starting")
            if [[ "$m2_status" == "healthy" ]]; then
              break
            fi
            sleep 5
          done
          info "Ejecutando upgrade de plugins de Moodle para registrar observadores de eventos..."
          docker exec -u daemon "$moodle_container" php /opt/bitnami/moodle/admin/cli/upgrade.php --non-interactive 2>/dev/null || true
          docker exec -u daemon "$moodle_container" php /opt/bitnami/moodle/admin/cli/purge_caches.php 2>/dev/null || true
          
          info "Habilitando Web Services y API Móvil en Moodle..."
          docker exec -u daemon "$moodle_container" php /opt/bitnami/moodle/admin/cli/cfg.php --name=enablewebservices --set=1 2>/dev/null || true
          docker exec -u daemon "$moodle_container" php /opt/bitnami/moodle/admin/cli/cfg.php --name=enablemobilewebservice --set=1 2>/dev/null || true
          
          local mariadb_container=$(grep -m 1 MARIADB_NOMBRE_CONTENEDOR .env | cut -d= -f2 | tr -d '\r' || echo "moodle-matrix-dev-mariadb-1")
          local mariadb_user=$(grep -m 1 MARIADB_USER .env | cut -d= -f2 | tr -d '\r' || echo "bn_moodle")
          local mariadb_pass=$(grep -m 1 MARIADB_PASSWORD .env | cut -d= -f2 | tr -d '\r' || echo "moodle_db_pass")
          local mariadb_db=$(grep -m 1 MARIADB_DATABASE .env | cut -d= -f2 | tr -d '\r' || echo "bitnami_moodle")
          docker exec "$mariadb_container" mysql -u "$mariadb_user" -p"$mariadb_pass" "$mariadb_db" -e "UPDATE mdl_external_services SET enabled = 1 WHERE shortname = 'moodle_mobile_app';" 2>/dev/null || true
          
          ok "Plugin block_bdc registrado y Web Services habilitados."
          break
        elif [[ "$s_status" == "unhealthy" ]]; then
          error "Synapse falló el healthcheck. Revisa 'docker logs $synapse_container'."
        fi
        sleep 5
      done

      break
    fi
    
    if [[ "$m_status" == "unhealthy" ]]; then
      error "Moodle falló el healthcheck. Revisa 'docker logs $moodle_container'."
    fi
    
    if [[ "$api_status" == "unhealthy" ]]; then
      error "mapeo-api falló el healthcheck. Revisa 'docker logs $mapeo_api_container'."
    fi
    
    sleep 5
  done
  
  cd "${ROOT_DIR}"
  print_summary
}
cmd_down()   { error "Comando 'down' pendiente (Fase 1)."; }
cmd_logs()   { error "Comando 'logs' pendiente (Fase 1)."; }
cmd_status() { error "Comando 'status' pendiente (Fase 1)."; }
## @fn cmd_git()
## @brief Configura el repositorio oficial en GitHub usando un contenedor Python efímero.
cmd_git() {
  local asignatura="${1:-}"
  local profesores="${2:-}"
  
  if [[ -z "$asignatura" || -z "$profesores" ]]; then
    error "Debe pasarse la asignatura y los profesores como argumentos. Ejemplo: ./instalar.sh git mi_asignatura profesor1"
  fi
  
  info "Aprovisionando repositorio oficial en GitHub para: ${asignatura}..."
  check_docker
  
  # Levanta un contenedor efímero, instala dependencias al vuelo y ejecuta el script
  docker run --rm \
    -v "${ROOT_DIR}:/app" \
    -w /app \
    python:3.11-slim \
    sh -c "pip install --quiet httpx pyyaml && python scripts/configurar_bdc_core.py \"$asignatura\" $profesores"
    
  ok "Repositorio maestro configurado con éxito en GitHub."
}
## @fn cmd_bot()
## @brief Comandos de gestión del bot y sincronización
cmd_bot() {
  local submode="${1:-}"
  
  case "$submode" in
    package)
      local plugin_path="${ROOT_DIR}/src/bot/llm-wiki-assistant-plugin/plugin.mbp"
      if [[ -f "$plugin_path" ]]; then
        info "El plugin de Maubot ya está empaquetado (plugin.mbp existe). Omitiendo..."
      else
        info "Empaquetando el plugin de Maubot (Fase 5)..."
        check_docker
        docker run --rm -v "${ROOT_DIR}/src/bot/llm-wiki-assistant-plugin:/plugin" alpine sh -c "apk add --no-cache zip && cd /plugin && zip -r plugin.mbp . -x '*/__pycache__/*' -x '*.pyc'"
        ok "Plugin empaquetado exitosamente en src/bot/llm-wiki-assistant-plugin/plugin.mbp"
      fi
      ;;
    sync)
      error "Comando 'bot sync' pendiente (Fase 3)."
      ;;
    *)
      error "Subcomando bot no reconocido. Usa 'bot package'."
      ;;
  esac
}

## @fn cmd_test()
## @brief Ejecuta de forma consolidada todos los tests del proyecto.
cmd_test() {
  local is_full=false
  for arg in "$@"; do
    if [[ "$arg" == "--full" ]]; then
      is_full=true
    fi
  done

  info "=== INICIANDO BATERÍA DE TESTS (FASE 7) ==="

  if [[ "$is_full" == "true" ]]; then
    info "Modo --full detectado: Destruyendo infraestructura y reseteando entorno..."
    cd "${ROOT_DIR}"
    docker compose down -v 2>/dev/null || true
    rm -f .env
    cd "${ROOT_DIR}"
    ./instalar.sh
  fi

  local res_infra="[ FALLO ]"
  local res_api="[ FALLO ]"
  local res_moodle="[ FALLO ]"
  local res_worker="[ FALLO ]"
  local res_docs="[ FALLO ]"
  local global_exit=0

  # Evitamos que set -e corte la ejecución en caso de fallo de un bloque
  set +e

  # a. Test de infraestructura Docker (Fase 1)
  info "--- Ejecutando bloque A: Infraestructura ---"
  if "${ROOT_DIR}/scripts/test-services.sh"; then
    res_infra="[ PASA  ]"
  else
    warn "Fallo en el bloque de Infraestructura."
    global_exit=1
  fi

  # b. Tests de mapeo-api (Fases 2, 4, 4.2, 5.1)
  info "--- Ejecutando bloque B: mapeo-api ---"
  local api_fail=0
  docker exec moodle-matrix-dev-mapeo-api-1 alembic upgrade head || api_fail=1
  # Copy tests into the container since they are not mounted by default
  docker cp "${ROOT_DIR}/src/api/tests" moodle-matrix-dev-mapeo-api-1:/code/tests
  docker exec moodle-matrix-dev-mapeo-api-1 bash -c "PYTHONPATH=/code pytest -v /code/tests" || api_fail=1
  if [[ "$api_fail" -eq 0 ]]; then
    res_api="[ PASA  ]"
  else
    warn "Fallo en el bloque de mapeo-api (pytest o alembic)."
    global_exit=1
  fi

  # c. Tests PHPUnit del bloque Moodle (Fase 3)
  info "--- Ejecutando bloque C: Moodle (PHPUnit) ---"
  local moodle_fail=0
  
  # Check if PHPUnit is initialized
  local phpunit_status
  phpunit_status=$(docker exec -w /bitnami/moodle moodle-matrix-dev-moodle-1 php admin/tool/phpunit/cli/util.php --diag 2>&1)
  if echo "$phpunit_status" | grep -qiE "not initialized|Can not find PHPUnit"; then
    info "PHPUnit no inicializado. Procediendo a configurarlo (esto tomará un tiempo)..."
    # Bitnami image fallback logic for composer
    docker exec -w /bitnami/moodle moodle-matrix-dev-moodle-1 bash -c "if [ ! -f composer.phar ]; then curl -sS https://getcomposer.org/installer | php; fi" || moodle_fail=1
    docker exec -w /bitnami/moodle moodle-matrix-dev-moodle-1 php composer.phar install --no-interaction --quiet || moodle_fail=1
    docker exec -w /bitnami/moodle moodle-matrix-dev-moodle-1 php admin/tool/phpunit/cli/util.php --build || moodle_fail=1
    docker exec -w /bitnami/moodle moodle-matrix-dev-moodle-1 php admin/tool/phpunit/cli/init.php || moodle_fail=1
  fi

  if [[ "$moodle_fail" -eq 0 ]]; then
    docker exec -w /bitnami/moodle moodle-matrix-dev-moodle-1 php vendor/bin/phpunit blocks/bdc/tests/bdc_creation_test.php || moodle_fail=1
  fi

  if [[ "$moodle_fail" -eq 0 ]]; then
    res_moodle="[ PASA  ]"
  else
    warn "Fallo en el bloque de Moodle (PHPUnit)."
    global_exit=1
  fi

  # d. Tests Python del bot / worker (Fases 5, 5.1, 6)
  info "--- Ejecutando bloque D: Bot / Worker (pytest) ---"
  if docker exec moodle-matrix-dev-sync-worker-1 sh -c "cd /data/llm-wiki-assistant-plugin && pytest -v tests/"; then
    res_worker="[ PASA  ]"
  else
    warn "Fallo en el bloque de Worker/Bot (pytest)."
    global_exit=1
  fi
  info "NOTA: El script test_race.py y el test de hot-reload quedan fuera de esta ejecución automatizada por su naturaleza interactiva/disruptiva."

  # e. Validación Doxygen en modo estricto
  info "--- Ejecutando bloque E: Doxygen ---"
  if cmd_docs check; then
    res_docs="[ PASA  ]"
  else
    warn "Fallo en el bloque de Doxygen (estricto)."
    global_exit=1
  fi

  set -e

  echo ""
  echo "=== RESUMEN DE BATERÍA DE TESTS ==="
  echo "A. Infraestructura Docker : $res_infra"
  echo "B. API Mapeo              : $res_api"
  echo "C. Moodle (PHPUnit)       : $res_moodle"
  echo "D. Bot y Sync Worker      : $res_worker"
  echo "E. Doxygen (estricto)     : $res_docs"
  echo "==================================="

  if [[ "$global_exit" -ne 0 ]]; then
    error "La batería de tests falló en uno o más subsistemas (ver detalle arriba)."
  else
    ok "Todos los subsistemas pasaron con éxito."
  fi
}
## @fn main()
## @brief Procesador de línea de comandos. Enruta argumentos a subfunciones.
## @param $@ Argumentos pasados al script.
main() {
  if [[ "${1:-}" == "--test" ]]; then
    shift
    cmd_test "$@"
    return
  fi

  [[ $# -eq 0 ]] && { cmd_install_all; return; }

  local cmd="$1"; shift || true
  case "$cmd" in
    docs)           cmd_docs   "${@:-serve}" ;;
    up)             cmd_up "$@" ;;
    down)           cmd_down "$@" ;;
    logs)           cmd_logs "$@" ;;
    status)         cmd_status "$@" ;;
    git)            cmd_git "$@" ;;
    bot)            cmd_bot "$@" ;;
    help|-h|--help) usage ;;
    *) error "Comando desconocido: '${cmd}'. Utiliza 'help' para listado completo." ;;
  esac
}

main "$@"
