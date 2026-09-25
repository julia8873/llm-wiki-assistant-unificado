FROM python:3.11-slim

WORKDIR /code

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY ./app /code/app

COPY ./alembic.ini /code/
COPY ./alembic /code/alembic

# Añadimos curl para el healthcheck de docker-compose
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Add a non-root user for security
RUN groupadd -g 1000 apiuser && useradd -r -u 1000 -g apiuser apiuser
RUN mkdir -p /data && chown -R apiuser:apiuser /code /data
USER apiuser

CMD ["sh", "-c", "alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port ${PORT_MAPEO_API} --proxy-headers --root-path \"${MAPEO_API_ROOT_PATH:-}\""]
