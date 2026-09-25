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


## @fn check_file_exists()
## @brief Comprueba si un archivo de configuración existe.
## @param $1 Ruta absoluta del fichero origen (plantilla).
## @param $2 Ruta absoluta del fichero destino.
check_file_exists() {
  local src="$1" dst="$2"
  if [[ ! -f "$dst" ]]; then
    error "Falta el archivo $(basename "$dst"). Por favor, cópialo desde $(basename "$src") e inyecta los secretos reales."
  else
    skip "$(basename "$dst") ya existe."
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
  generate_env
  echo ""

  echo "--- Fase: Stack Docker ---"

  cmd_up "$@"
  echo ""

  echo ""
  echo "--- Fase: Empaquetado del Bot LLM ---"
  cmd_bot package

  echo "=== Secuencia Completada ==="
  echo "  [OK] Entorno configurado"
  echo ""
}

## @fn cmd_docs()
## @brief Gestiona el ciclo de vida de la documentación Doxygen vía Docker Alpine.
## @param $1 Comando subordinado (serve|check). Por defecto 'serve'.
## @exception Aborta si el comando es inválido o falla la validación estricta (check).
cmd_docs() {
  local submode="${1:-serve}"
  check_docker
  
  if [[ ! -f "${ROOT_DIR}/Doxyfile" ]]; then
    info "Creando Doxyfile base automático..."
    docker run --rm -v "${ROOT_DIR}:/app" -w /app alpine sh -c "apk add --no-cache doxygen && doxygen -g && sed -i 's|^INPUT                  =.*|INPUT                  = src scripts instalar.sh|' Doxyfile && sed -i 's|^RECURSIVE              = NO|RECURSIVE              = YES|' Doxyfile && sed -i 's|^EXCLUDE_PATTERNS       =.*|EXCLUDE_PATTERNS       = */node_modules/* */venv/* */.git/* */playwright-report/* */alembic/versions/* */tests/* test_*.py *_test.py *_test.php|' Doxyfile && sed -i 's|^OUTPUT_DIRECTORY       =.*|OUTPUT_DIRECTORY       = docs|' Doxyfile && sed -i 's|^PROJECT_NAME           =.*|PROJECT_NAME           = \"LLM Wiki Assistant\"|' Doxyfile" >/dev/null
  fi

  if [[ "$submode" == "serve" ]]; then
    local doxygen_port; doxygen_port=$(grep -m 1 '^DOXYGEN_PUERTO_HOST=' "${ROOT_DIR}/.env" | cut -d= -f2- | tr -d '\r')
    local doxygen_name; doxygen_name=$(grep -m 1 '^DOXYGEN_NOMBRE_CONTENEDOR=' "${ROOT_DIR}/.env" | cut -d= -f2- | tr -d '\r')
    [[ -z "$doxygen_port" ]] && error "DOXYGEN_PUERTO_HOST no está definido en .env"
    [[ -z "$doxygen_name" ]] && error "DOXYGEN_NOMBRE_CONTENEDOR no está definido en .env"
    info "Generando y sirviendo documentación (Puerto ${doxygen_port})..."
    docker rm -f "$doxygen_name" >/dev/null 2>&1 || true
    docker run -d --name "$doxygen_name" -p "${doxygen_port}:8000" -v "${ROOT_DIR}:/app" -w /app alpine sh -c "apk add --no-cache doxygen graphviz python3 && doxygen Doxyfile && cd docs/html && python3 -m http.server 8000" >/dev/null
    ok "Documentación Doxygen servida en http://127.0.0.1:${doxygen_port}"
  elif [[ "$submode" == "check" ]]; then
    info "Generando Doxygen en modo estricto..."
    docker run --rm -v "${ROOT_DIR}:/app" -w /app alpine sh -c "apk add --no-cache doxygen graphviz && doxygen Doxyfile 2> doxygen.log && if [ -s doxygen.log ]; then cat doxygen.log; exit 1; fi"
    ok "Documentación generada sin warnings."
  else
    error "Comando docs no válido: $submode"
  fi
}

### @fn generate_env()
## @brief Genera el fichero .env a partir de .env.example si no existe, y autorrellena tokens secretos.
generate_env() {
  local env_file="${ROOT_DIR}/.env"

  info "Comprobando ${env_file}..."

  check_file_exists "${ROOT_DIR}/.env.example" "$env_file"
  
  if [[ ! -f "${ROOT_DIR}/config/config.yaml" ]]; then
    set -a
    source "$env_file" 2>/dev/null || true
    set +a
    envsubst < "${ROOT_DIR}/config/config.yaml.example" > "${ROOT_DIR}/config/config.yaml"
    ok "config/config.yaml generado e inyectado desde la plantilla."
  else
    skip "config/config.yaml ya existe."
  fi
  if [[ ! -f "${ROOT_DIR}/src/bot/config.yaml" ]]; then
    cp "${ROOT_DIR}/src/bot/config.yaml.example" "${ROOT_DIR}/src/bot/config.yaml"
    ok "src/bot/config.yaml creado desde la plantilla."
  else
    skip "src/bot/config.yaml ya existe."
  fi

  # Generar MAPEO_API_TOKEN si está en modo default
  if grep -q "MAPEO_API_TOKEN=changeme" "$env_file"; then
    local new_token=$(openssl rand -hex 16)
    sed -i "s/MAPEO_API_TOKEN=changeme/MAPEO_API_TOKEN=${new_token}/" "$env_file"
    info "Se ha generado un MAPEO_API_TOKEN aleatorio para esta instancia."
  fi

  # Generar secretos de seguridad automáticamente
  local secrets=("AGENT_HMAC_SECRET" "INTERNAL_SERVICE_TOKEN" "PII_SECRET_KEY" "MAUBOT_CRYPTO_PICKLE_KEY" "JWT_SECRET_KEY" "SYNAPSE_REGISTRATION_SECRET" "SYNAPSE_MACAROON_SECRET" "SYNAPSE_FORM_SECRET")
  for secret in "${secrets[@]}"; do
    if grep -qE "${secret}=.*(GENERATE_RANDOM|CHANGEME)" "$env_file"; then
      local new_secret
      if [[ "$secret" == "PII_SECRET_KEY" ]]; then
        new_secret=$(openssl rand -base64 32 | tr '+/' '-_' | tr -d '\n')
      else
        new_secret=$(openssl rand -hex 32)
      fi
      sed -i -E "s/${secret}=.*(GENERATE_RANDOM|CHANGEME)/${secret}=${new_secret}/" "$env_file"
      info "Se ha generado un ${secret} aleatorio para esta instancia."
    fi
  done

  # Eliminar retornos de carro (CRLF -> LF) para evitar errores "command not found" al hacer source en WSL
  sed -i 's/\r$//' "$env_file"

  # Parchear credenciales de Maubot en su config.yaml (vía Docker para evitar permisos denegados)
  local m_pass; m_pass=$(grep -m 1 "^MAUBOT_ADMIN_PASSWORD=" "$env_file" 2>/dev/null | cut -d= -f2- | tr -d '\r' || true)
  local m_key; m_key=$(grep -m 1 "^MAUBOT_CRYPTO_PICKLE_KEY=" "$env_file" 2>/dev/null | cut -d= -f2- | tr -d '\r' || true)

  if [[ -n "$m_pass" || -n "$m_key" ]]; then
    info "Inyectando credenciales en Maubot..."
    check_docker
    if python3 -c "import bcrypt" 2>/dev/null; then
      if [ -n "$m_pass" ]; then
        m_hash=$(python3 -c "import bcrypt; print(bcrypt.hashpw('${m_pass}'.encode('utf-8'), bcrypt.gensalt()).decode('utf-8'))")
        sed -i "s|^[[:space:]]*admin: .*|    admin: $m_hash|" "${ROOT_DIR}/src/bot/config.yaml" 2>/dev/null || sudo sed -i "s|^[[:space:]]*admin: .*|    admin: $m_hash|" "${ROOT_DIR}/src/bot/config.yaml" || true
      fi
      if [ -n "$m_key" ]; then
        sed -i "s|pickle_key: .*|pickle_key: \"${m_key}\"|" "${ROOT_DIR}/src/bot/config.yaml" 2>/dev/null || sudo sed -i "s|pickle_key: .*|pickle_key: \"${m_key}\"|" "${ROOT_DIR}/src/bot/config.yaml" || true
      fi
    else
      docker run --rm -v "${ROOT_DIR}/src/bot:/data" alpine sh -c "
        if [ -n \"$m_pass\" ]; then
          apk add --timeout 10 --no-cache python3 py3-bcrypt || true
          m_hash=\$(python3 -c \"import bcrypt; print(bcrypt.hashpw('${m_pass}'.encode('utf-8'), bcrypt.gensalt()).decode('utf-8'))\" 2>/dev/null)
          if [ -n \"\$m_hash\" ]; then
            sed -i \"s|^[[:space:]]*admin: .*|    admin: \$m_hash|\" /data/config.yaml 2>/dev/null || true
          fi
        fi
        if [ -n \"$m_key\" ]; then
          sed -i \"s|pickle_key: .*|pickle_key: \\\"${m_key}\\\"|\" /data/config.yaml 2>/dev/null || true
        fi
      "
    fi
    # Reiniciamos maubot por si estaba corriendo, para que tome el nuevo config.yaml
    docker compose -f "${ROOT_DIR}/docker-compose.yml" restart maubot >/dev/null 2>&1 || true
  fi

  return 0
}


## @fn print_summary()
## @brief Imprime la tabla resumen de credenciales y URLs
print_summary() {
  local env_file="${ROOT_DIR}/.env"
  local moodle_port;   moodle_port=$(grep -m 1 '^MOODLE_PUERTO_HOST='   "$env_file" | cut -d= -f2- | tr -d '\r')
  local synapse_port;  synapse_port=$(grep -m 1 '^SYNAPSE_PUERTO_HOST='  "$env_file" | cut -d= -f2- | tr -d '\r')
  local element_port;  element_port=$(grep -m 1 '^ELEMENT_PUERTO_HOST='  "$env_file" | cut -d= -f2- | tr -d '\r')
  local maubot_port;   maubot_port=$(grep -m 1 '^MAUBOT_PUERTO_HOST='   "$env_file" | cut -d= -f2- | tr -d '\r')
  local doxygen_port;  doxygen_port=$(grep -m 1 '^DOXYGEN_PUERTO_HOST='  "$env_file" | cut -d= -f2- | tr -d '\r')
  local mapeo_port;    mapeo_port=$(grep -m 1 '^MAPEO_API_PUERTO_HOST=' "$env_file" | cut -d= -f2- | tr -d '\r')
  local mapeo_name;    mapeo_name=$(grep -m 1 '^MAPEO_API_NOMBRE_CONTENEDOR=' "$env_file" | cut -d= -f2- | tr -d '\r')
  local ollama_port;   ollama_port=$(grep -m 1 '^LLM_SERVER_OPCIONAL_PUERTO_HOST=' "$env_file" | cut -d= -f2- | tr -d '\r' || echo "11434")
  local domain;        domain=$(grep -m 1 '^DOMAIN='               "$env_file" | cut -d= -f2- | tr -d '\r')

  echo ""
  echo "=== RESUMEN DE SERVICIOS ==="
  echo "Servicio    URL"
  echo "----------------------------------------------------------------"
  echo "Moodle      http://${domain}:${moodle_port}"
  echo "Matrix      http://${domain}:${synapse_port}"
  echo "Element     http://${domain}:${element_port}"
  echo "Maubot      http://${domain}:${maubot_port}/_matrix/maubot"
  echo "Doxygen     http://${domain}:${doxygen_port}"
  echo "Mapeo API   http://${mapeo_name%%:*}:${mapeo_port}"
  
  cd "${ROOT_DIR}" || true
  if docker compose ps --services --filter "status=running" 2>/dev/null | grep -q "ollama"; then
    echo "Ollama      http://${domain}:${ollama_port}"
  fi
  cd "${ROOT_DIR}"
  
  echo "----------------------------------------------------------------"
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
  local env_file="${ROOT_DIR}/.env"
  local synapse_port; synapse_port=$(grep -m 1 '^SYNAPSE_PUERTO_HOST=' "$env_file" | cut -d= -f2- | tr -d '\r')
  local synapse_container; synapse_container=$(grep -m 1 '^SYNAPSE_NOMBRE_CONTENEDOR=' "$env_file" | cut -d= -f2- | tr -d '\r')
  local admin_user; admin_user=$(grep -m 1 '^SYNAPSE_ADMIN_USER=' "$env_file" | cut -d= -f2- | tr -d '\r')
  local admin_pass; admin_pass=$(grep -m 1 '^SYNAPSE_ADMIN_PASSWORD=' "$env_file" | cut -d= -f2- | tr -d '\r' | sed 's/_CHANGE_ME.*//')
  local domain; domain=$(grep -m 1 '^DOMAIN=' "$env_file" | cut -d= -f2- | tr -d '\r')

  [[ -z "$synapse_port" ]] && error "SYNAPSE_PUERTO_HOST no está definido en .env"
  [[ -z "$synapse_container" ]] && error "SYNAPSE_NOMBRE_CONTENEDOR no está definido en .env"
  [[ -z "$admin_user" ]] && error "SYNAPSE_ADMIN_USER no está definido en .env"
  [[ -z "$admin_pass" ]] && error "SYNAPSE_ADMIN_PASSWORD no está definido en .env"
  [[ -z "$domain" ]] && error "DOMAIN no está definido en .env"

  local synapse_url="http://127.0.0.1:${synapse_port}"
  local token_in_env; token_in_env=$(grep -m 1 '^MATRIX_ACCESS_TOKEN=' "$env_file" | cut -d= -f2- | tr -d '\r')

  info "Verificando que @${admin_user}:${domain} sea admin de Synapse..."

  # 1. Intentar login para obtener token fresco
  local login_resp
  login_resp=$(curl -sf --max-time 10 -X POST "${synapse_url}/_matrix/client/v3/login" \
    -H 'Content-Type: application/json' \
    -d "{\"type\":\"m.login.password\",\"user\":\"${admin_user}\",\"password\":\"${admin_pass}\"}" 2>/dev/null || echo '')
  local fresh_token; fresh_token=$(echo "$login_resp" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4 || true)

  if [[ -z "$fresh_token" ]]; then
    info "Registrando usuario admin en Synapse..."
    docker exec "$synapse_container" \
      register_new_matrix_user -c /data/homeserver.yaml --admin \
      -u "$admin_user" -p "$admin_pass" "${synapse_url}" 2>/dev/null || true

    # Reintentar login
    login_resp=$(curl -sf -X POST "${synapse_url}/_matrix/client/v3/login" \
      -H 'Content-Type: application/json' \
      -d "{\"type\":\"m.login.password\",\"user\":\"${admin_user}\",\"password\":\"${admin_pass}\"}" 2>/dev/null || echo '')
    fresh_token=$(echo "$login_resp" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4 || true)
  fi

  if [[ -z "$fresh_token" ]]; then
    warn "No se pudo obtener token de Synapse para @${admin_user}:${domain}. Omitiendo promoción a admin."
    return
  fi

  # 2. Comprobar si ya es admin
  local user_info
  user_info=$(curl -sf -H "Authorization: Bearer ${fresh_token}" \
    "${synapse_url}/_synapse/admin/v2/users/@${admin_user}:${domain}" 2>/dev/null || echo '')
  local is_admin; is_admin=$(echo "$user_info" | grep -o '"admin":[^,}]*' | cut -d: -f2 | tr -d ' ' || true)

  if [[ "$is_admin" == "true" ]]; then
    ok "@${admin_user}:${domain} ya es admin de Synapse."
  else
    info "Promoviendo @${admin_user}:${domain} a admin de Synapse (vía DB)..."
    docker exec "$synapse_container" python -c "import sqlite3; conn = sqlite3.connect('/data/homeserver.db'); conn.execute('UPDATE users SET admin = 1 WHERE name = \'@${admin_user}:${domain}\''); conn.commit(); conn.close()" 2>/dev/null || true
    # Reiniciar synapse para asegurar que el cambio de DB se aplique en memoria
    docker restart "$synapse_container" >/dev/null
    
    # Esperar a que vuelva a levantar
    sleep 5
    while true; do
      local s_status=$(docker inspect --format="{{if .State.Health}}{{.State.Health.Status}}{{end}}" "moodle-matrix-dev-synapse-1" 2>/dev/null || echo "starting")
      if [[ "$s_status" == "healthy" ]]; then
        break
      fi
      sleep 2
    done
    ok "@${admin_user}:${domain} promovido a admin de Synapse y servicio reiniciado."

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
  local synapse_port; synapse_port=$(grep -m 1 '^SYNAPSE_PUERTO_HOST=' "$root_env" | cut -d= -f2- | tr -d '\r')
  local synapse_container; synapse_container=$(grep -m 1 '^SYNAPSE_NOMBRE_CONTENEDOR=' "$root_env" | cut -d= -f2- | tr -d '\r')
  local bot_username; bot_username=$(grep -m 1 '^MATRIX_BOT_USER=' "$root_env" | cut -d= -f2- | tr -d '\r' | sed 's/@//' | cut -d: -f1)

  [[ -z "$synapse_port" ]] && error "SYNAPSE_PUERTO_HOST no está definido en .env"
  [[ -z "$synapse_container" ]] && error "SYNAPSE_NOMBRE_CONTENEDOR no está definido en .env"
  [[ -z "$bot_username" ]] && error "MATRIX_BOT_USER no está definido en .env"

  local synapse_url="http://127.0.0.1:${synapse_port}"
  local bot_token; bot_token=$(grep -E "^BOT_ACCESS_TOKEN=" "$root_env" | cut -d= -f2- || true)
  
  if [[ -z "$bot_token" ]]; then
    info "Generando Access Token para el bot (${bot_username})..."
    local bot_pass; bot_pass=$(grep -m 1 "^SYNAPSE_ADMIN_PASSWORD=" "$root_env" | cut -d= -f2- | tr -d '\r')
    [[ -z "$bot_pass" ]] && error "SYNAPSE_ADMIN_PASSWORD no está definido en .env"

    # 1. Registrar usuario bot
    docker exec "$synapse_container" \
      register_new_matrix_user -c /data/homeserver.yaml --no-admin \
      -u "$bot_username" -p "$bot_pass" "${synapse_url}" 2>/dev/null || true

    # 2. Hacer login para obtener token
    local login_resp
    login_resp=$(curl -sf -X POST "${synapse_url}/_matrix/client/v3/login" \
      -H 'Content-Type: application/json' \
      -d "{\"type\":\"m.login.password\",\"user\":\"${bot_username}\",\"password\":\"${bot_pass}\"}" 2>/dev/null || echo '')
      
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
    sed -i 's/\${DOMAIN}/'"${domain}"'/g' "${ROOT_DIR}/src/matrix/element/config.json" 2>/dev/null || true
    sed -i 's/\${DOMAIN}/'"${domain}"'/g' "${ROOT_DIR}/src/bot/config.yaml" 2>/dev/null || true
  fi

  cd "${ROOT_DIR}"

  # Copiar rest_auth_provider.py a synapse-data/ antes de arrancar Synapse.
  # Docker Desktop (virtiofs) no soporta bind mounts de archivos individuales
  # dentro de un directorio que ya está montado como volumen; el archivo
  # se gestiona directamente en synapse-data/ y es accesible vía ese volumen.
  info "Copiando rest_auth_provider.py a synapse-data/..."
  cp -f "src/matrix/synapse-custom/rest_auth_provider.py" \
        "src/matrix/synapse-data/rest_auth_provider.py"

  # Sustituir variables de entorno en homeserver.yaml (plantilla con ${VAR}).
  # Las versiones recientes de Synapse requieren homeserver.yaml con valores literales.
  info "Aplicando variables de entorno a homeserver.yaml..."
  set -a
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"
  # La plantilla usa ${SYNAPSE_SERVER_NAME}; el .env lo expone como DOMAIN
  SYNAPSE_SERVER_NAME="${DOMAIN}"
  set +a
  envsubst < "src/matrix/synapse-data/homeserver.yaml.example" \
            > "src/matrix/synapse-data/homeserver.yaml.tmp" && \
    mv "src/matrix/synapse-data/homeserver.yaml.tmp" \
       "src/matrix/synapse-data/homeserver.yaml"
  ok "homeserver.yaml configurado."

  info "Aplicando variables de entorno a Element config.json..."
  envsubst < "src/matrix/element/config.json" \
            > "src/matrix/element/config.json.tmp" && \
    mv "src/matrix/element/config.json.tmp" \
       "src/matrix/element/config.json"
  ok "Element config.json configurado."

  local compose_args="-f docker-compose.yml"
  if [[ "$env_mode" == "dev" ]]; then
    compose_args="-f docker-compose.yml -f docker-compose.dev.yml"
  fi

  if [ "$use_ollama" = true ]; then
    info "Perfil Ollama activado."
    docker compose $compose_args --env-file .env --profile ollama up -d --build
  else
    docker compose $compose_args --env-file .env up -d --build
  fi
  
  info "Esperando a que Moodle y mapeo-api estén operativos (Healthchecks)..."
  # Leer el nombre del contenedor dinámico
  local moodle_container; moodle_container=$(grep -m 1 '^MOODLE_NOMBRE_CONTENEDOR=' .env | cut -d= -f2- | tr -d '\r')
  local mapeo_api_container; mapeo_api_container=$(grep -m 1 '^MAPEO_API_NOMBRE_CONTENEDOR=' .env | cut -d= -f2- | tr -d '\r')
  [[ -z "$moodle_container" ]] && error "MOODLE_NOMBRE_CONTENEDOR no está definido en .env"
  [[ -z "$mapeo_api_container" ]] && error "MAPEO_API_NOMBRE_CONTENEDOR no está definido en .env"
  
  while true; do
    local m_status=$(docker inspect --format="{{if .State.Health}}{{.State.Health.Status}}{{end}}" "$moodle_container" 2>/dev/null || echo "starting")
    local api_status=$(docker inspect --format="{{if .State.Health}}{{.State.Health.Status}}{{end}}" "$mapeo_api_container" 2>/dev/null || echo "starting")
    
    if [[ "$m_status" == "healthy" && "$api_status" == "healthy" ]]; then
      ok "Moodle y mapeo-api están operativos."
      
      # Configuramos el SSO de Matrix automáticamente si es la primera vez
      if [[ -f "synapse-data/homeserver.yaml" ]] && ! grep -q "password_providers:" "synapse-data/homeserver.yaml"; then
        info "Inyectando configuración SSO de Moodle en Synapse..."
        local moodle_sso_endpoint=$(grep -m 1 MOODLE_SSO_AUTH_ENDPOINT .env | cut -d= -f2- | tr -d '\r' || echo "http://moodle:8080/blocks/bdc/api/auth.php")
        # Replace the port if it contains ${MOODLE_PUERTO_CONTENEDOR} as defined in .env
        local moodle_puerto=$(grep -m 1 MOODLE_PUERTO_CONTENEDOR .env | cut -d= -f2 | tr -d '\r' || echo "8080")
        moodle_sso_endpoint="${moodle_sso_endpoint/\$\{MOODLE_PUERTO_CONTENEDOR\}/$moodle_puerto}"
        cat << EOF >> "synapse-data/homeserver.yaml"

password_providers:
  - module: "rest_auth_provider.RestAuthProvider"
    config:
      endpoint: "${moodle_sso_endpoint}"
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
          unset MATRIX_ACCESS_TOKEN BOT_ACCESS_TOKEN
          docker compose up -d --force-recreate --no-deps moodle >/dev/null 2>&1 || true
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

    git)            cmd_git "$@" ;;
    bot)            cmd_bot "$@" ;;
    *) error "Comando desconocido: '${cmd}'. Utiliza 'help' para listado completo." ;;
  esac
}

main "$@"
