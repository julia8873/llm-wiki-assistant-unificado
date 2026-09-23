#!/usr/bin/env bash
## @file limpiar.sh
## @brief Script para resetear completamente el entorno, borrando bases de datos, imágenes y configuraciones generadas.

set -euo pipefail

echo "======================================================="
echo " LIMPIEZA PROFUNDA DEL ENTORNO LLM WIKI ASSISTANT"
echo "======================================================="
echo ""

# 1. Detener Docker, borrar volúmenes (bases de datos) e imágenes
echo "[INFO] Deteniendo contenedores, borrando volúmenes e imágenes declaradas..."
docker compose down -v --rmi all --remove-orphans || echo "[WARN] Hubo un problema al ejecutar docker compose down."

echo "[INFO] Limpiando la caché de construcción (build cache) e imágenes huérfanas..."
# Borramos la caché de Docker para asegurarnos de que la próxima vez reconstruya todo desde cero
docker builder prune -f || true
docker image prune -f || true

echo "[INFO] Borrando bases de datos SQLite locales (Maubot y Synapse)..."
rm -f src/bot/*.db src/bot/*.db-shm src/bot/*.db-wal
rm -f src/matrix/synapse-data/*.db src/matrix/synapse-data/*.db-shm src/matrix/synapse-data/*.db-wal
rm -f src/matrix/synapse-data/*.log

echo ""
echo "[ OK ] ¡Entorno y bases de datos completamente limpios!"
