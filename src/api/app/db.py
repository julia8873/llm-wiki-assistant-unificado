"""! @file db.py
@brief Configuración de la base de datos (SQLAlchemy).

Se encarga de la conexión a la base de datos de producción (PostgreSQL)
y de la definición del ORM para la tabla de mapeos.
"""

from sqlalchemy import Column, Integer, String, DateTime, UniqueConstraint, create_engine
from sqlalchemy.orm import declarative_base, sessionmaker
from datetime import datetime
import os
from app.core.config import settings

DATABASE_URL = settings.DATABASE_URL
engine = create_engine(DATABASE_URL, echo=False)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

class MapeoDB(Base):
    """!
    @brief Modelo ORM para la tabla 'mapeos'.
    @details Mantiene la relación entre un estudiante de Moodle (por su curso) y
    sus correspondientes recursos externos (GitHub y Matrix).
    """
    __tablename__ = "mapeos"
    __table_args__ = (
        UniqueConstraint("moodle_user_id", "moodle_course_id", name="uq_user_course"),
    )

    id = Column(Integer, primary_key=True, index=True)
    moodle_user_id = Column(Integer, nullable=False)
    moodle_course_id = Column(Integer, nullable=False)
    repo_url = Column(String, nullable=True)
    official_repo_url = Column(String, nullable=True)
    git_provider = Column(String, nullable=False, default="github")
    matrix_room_id = Column(String, nullable=True)
    estado = Column(String, default="PENDIENTE_GIT")
    is_teacher = Column(Integer, default=0)
    moodle_username = Column(String, nullable=True)
    moodle_course_name = Column(String, nullable=True)
    course_close_date = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

class EventosBotDB(Base):
    """!
    @brief Modelo ORM para la tabla 'eventos_bot'.
    @details Registra los eventos que el bot produce y envía al feed.
    """
    __tablename__ = "eventos_bot"

    id = Column(Integer, primary_key=True, index=True)
    matrix_room_id = Column(String, nullable=False, index=True)
    commit_sha = Column(String, nullable=False, unique=True, index=True)
    tipo_evento = Column(String, nullable=False)
    timestamp = Column(String, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

def get_session():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
