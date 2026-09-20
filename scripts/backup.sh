#!/bin/bash

# Este script realiza un backup de la base de datos de PostgreSQL y de Redis.
# Además, aplica una política de retención para evitar que el disco se llene.

# si algún comando falla, se detiene el script
set -e

BACKUP_DIR="${BACKUP_DIR:-/backups}"
mkdir -p "$BACKUP_DIR"

# generar marca de tiempo para que los archivos no se sobreescriban
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

echo "[INFO] Iniciando backup: $TIMESTAMP"

# 1. Backup de mapeo_db (contiene relaciones entre alumnos, repositorios y salas de Matrix)
PG_BACKUP_FILE="$BACKUP_DIR/mapeo_${TIMESTAMP}.dump"
echo "[INFO] Generando backup de PostgreSQL en $PG_BACKUP_FILE..."
PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump -h postgres -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -Fc -f "$PG_BACKUP_FILE"

# 2. Backup de Redis (almacena información para trabajos pendientes para metrics_worker)
REDIS_BACKUP_FILE="$BACKUP_DIR/redis_${TIMESTAMP}.tar.gz"
echo "[INFO] Generando backup del AOF de Redis en $REDIS_BACKUP_FILE..."
if [ -d "/redis_data/appendonlydir" ]; then
    tar -czf "$REDIS_BACKUP_FILE" -C /redis_data appendonlydir
else
    echo "[WARN] Directorio appendonlydir no encontrado en /redis_data. Verifique que AOF está habilitado."
    tar -czf "$REDIS_BACKUP_FILE" -C / redis_data
fi

echo "[INFO] Backups generados correctamente."

# 3. Política de Retención (para no llenar el disco)
echo "[INFO] Aplicando política de retención..."

# Reglas automáticas para evitar que el disco se llene (Retención Semanal):
# 1. Corto plazo (0 a 7 días): Se conservan TODAS las copias de seguridad de la última semana.
# 2. Medio plazo (7 a 30 días): De los archivos antiguos, se borran todos excepto los que se hicieron en Domingo (1 por semana).
# 3. Largo plazo (+30 días): Se borra cualquier copia que tenga más de un mes.

# Eliminamos ficheros más antiguos de 30 días (las últimas 4 semanas de margen)
find "$BACKUP_DIR" -type f -name "mapeo_*.dump" -mtime +30 -exec rm {} \;
find "$BACKUP_DIR" -type f -name "redis_*.tar.gz" -mtime +30 -exec rm {} \;

# Para los ficheros que tienen entre 7 y 30 días, si no se generaron un Domingo (día 7 de la semana), los borramos.
# find $BACKUP_DIR -mtime +7 -mtime -30. Iteramos.
for file in "$BACKUP_DIR"/mapeo_*.dump "$BACKUP_DIR"/redis_*.tar.gz; do
    if [ -f "$file" ]; then
        # Verificar si tiene más de 7 días
        if [ $(find "$file" -mtime +7 -print) ]; then
            # Obtener el día de la semana en el que se creó/modificó el archivo (1-7, 7 es Domingo)
            file_ts=$(stat -c %Y "$file")
            file_dow=$(date -d "@$file_ts" +%u)
            if [ "$file_dow" -ne 7 ]; then
                echo "Eliminando backup antiguo no semanal: $file"
                rm -f "$file"
            fi
        fi
    fi
done

echo "[INFO] Proceso de backup finalizado exitosamente."
