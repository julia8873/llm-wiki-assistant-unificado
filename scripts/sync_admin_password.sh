#!/bin/bash
# Sincroniza la contraseña del admin entre Moodle, Matrix (Synapse) y el .env.
# Uso:
#   ./scripts/sync_admin_password.sh <nueva_password>
#   ./scripts/sync_admin_password.sh   # Reutiliza MOODLE_PASSWORD del .env

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "[ERROR] No se encuentra el archivo .env en ${ROOT_DIR}" >&2
  exit 1
fi

# Leer variables necesarias del entorno
MOODLE_CONTAINER=$(grep -m 1 '^MOODLE_NOMBRE_CONTENEDOR=' "$ENV_FILE" | cut -d= -f2- | tr -d '\r')
SYNAPSE_CONTAINER=$(grep -m 1 '^SYNAPSE_NOMBRE_CONTENEDOR=' "$ENV_FILE" | cut -d= -f2- | tr -d '\r')
SYNAPSE_PORT=$(grep -m 1 '^SYNAPSE_PUERTO_HOST=' "$ENV_FILE" | cut -d= -f2- | tr -d '\r')
ADMIN_USER=$(grep -m 1 '^MOODLE_USERNAME=' "$ENV_FILE" | cut -d= -f2- | tr -d '\r')
DOMAIN=$(grep -m 1 '^DOMAIN=' "$ENV_FILE" | cut -d= -f2- | tr -d '\r')
PG_CONTAINER=$(grep -m 1 '^POSTGRES_NOMBRE_CONTENEDOR=' "$ENV_FILE" | cut -d= -f2- | tr -d '\r' || echo "moodle-matrix-dev-postgres-1")
PG_USER=$(grep -m 1 '^POSTGRES_USER=' "$ENV_FILE" | cut -d= -f2- | tr -d '\r' || echo "mapeo_user")
PG_DB=$(grep -m 1 '^POSTGRES_DB=' "$ENV_FILE" | cut -d= -f2- | tr -d '\r' || echo "mapeo_db")

if [[ $# -ge 1 && -n "$1" ]]; then
  NEW_PASS="$1"
else
  NEW_PASS=$(grep -m 1 '^MOODLE_PASSWORD=' "$ENV_FILE" | cut -d= -f2- | tr -d '\r')
  echo "[INFO] No se indico password; usando MOODLE_PASSWORD actual: ${NEW_PASS}"
fi

echo "[*] Sincronizando credenciales de ${ADMIN_USER}..."

# 1. Actualizar contraseña en Moodle (CLI de Bitnami)
if docker ps --format '{{.Names}}' | grep -q "^${MOODLE_CONTAINER}$"; then
  docker exec "$MOODLE_CONTAINER" php /opt/bitnami/moodle/admin/cli/change_password.php \
    --username="$ADMIN_USER" \
    --newpassword="$NEW_PASS" >/dev/null
  echo "[OK] Password actualizada en Moodle."
else
  echo "[WARN] Contenedor de Moodle parado; se omite cambio en su base de datos."
fi

# 2. Login en Synapse vía SSO de Moodle para validar y sacar token nuevo
SYNAPSE_URL="http://127.0.0.1:${SYNAPSE_PORT}"
LOGIN_RESP=$(curl -sf --max-time 10 -X POST "${SYNAPSE_URL}/_matrix/client/v3/login" \
  -H 'Content-Type: application/json' \
  -d "{\"type\":\"m.login.password\",\"user\":\"${ADMIN_USER}\",\"password\":\"${NEW_PASS}\"}" 2>/dev/null || echo '')

FRESH_TOKEN=$(echo "$LOGIN_RESP" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4 || true)

if [[ -z "$FRESH_TOKEN" ]]; then
  echo "[ERROR] Fallo el login en Synapse con la nueva password." >&2
  echo "Detalle: ${LOGIN_RESP}" >&2
  exit 1
fi
echo "[OK] Login correcto en Synapse."

# 3. Asegurar que tiene permisos admin en PostgreSQL
if docker ps --format '{{.Names}}' | grep -q "^${PG_CONTAINER}$"; then
  docker exec "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DB" \
    -c "UPDATE users SET admin = 1 WHERE name = '@${ADMIN_USER}:${DOMAIN}';" >/dev/null 2>&1 || true
fi

# 4. Actualizar .env
sed -i "s|^MOODLE_PASSWORD=.*|MOODLE_PASSWORD=${NEW_PASS}|" "$ENV_FILE"
sed -i "s|^SYNAPSE_ADMIN_PASSWORD=.*|SYNAPSE_ADMIN_PASSWORD=${NEW_PASS}|" "$ENV_FILE"
sed -i "s|^MATRIX_ACCESS_TOKEN=.*|MATRIX_ACCESS_TOKEN=${FRESH_TOKEN}|" "$ENV_FILE"
echo "[OK] Archivo .env actualizado."

# 5. Reiniciar Moodle para que cargue el MATRIX_ACCESS_TOKEN nuevo
cd "$ROOT_DIR"
docker compose up -d --no-deps moodle >/dev/null 2>&1 || true
echo "[OK] Moodle recargado con el nuevo token."

echo "[DONE] Password sincronizada: ${ADMIN_USER} (@${ADMIN_USER}:${DOMAIN})"
