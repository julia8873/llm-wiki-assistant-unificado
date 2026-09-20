import logging
from logging.config import fileConfig

from sqlalchemy import engine_from_config
from sqlalchemy import pool
from alembic import context
import os
import sys

# para acceder a src/api/app/db.py
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from app.db import Base, DATABASE_URL

# Lee de src/api/ambelic.ini para la configuración
config = context.config

# Configurar como se ven los logs por la terminal
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# Pasamos la estructura de las tablas para que Alembic sepa cómo deberían ser
target_metadata = Base.metadata

def run_migrations_offline() -> None:
    """Modo sin conexión: Genera las instrucciones SQL pero no las ejecuta en la base de datos."""
    url = DATABASE_URL
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Modo con conexión: Se conecta a la base de datos de verdad y aplica los cambios."""

    # coger contraseña de base de datos de 
    configuration = config.get_section(config.config_ini_section)
    configuration["sqlalchemy.url"] = DATABASE_URL
    
    # Crea el motor de conexión a la base de datos:

    # Crea el motor de conexión a la base de datos:
    # 1. Gestiona la comunicación de red a bajo nivel (TCP/IP) con el servidor.
    # 2. Traduce las órdenes genéricas de Python al PostgreSQL.
    connectable = engine_from_config(
        configuration,
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    # Se conecta y ejecuta los cambios
    with connectable.connect() as connection:
        context.configure(
            connection=connection, target_metadata=target_metadata
        )

        with context.begin_transaction():
            context.run_migrations()


# Alembic decide automáticamente si arrancar en modo offline u online
if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
