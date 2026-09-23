# SecuredView backend — portable image (Render / Koyeb / HF Spaces / any $0 host)
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
      libpq5 curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# App code only (no venv, no .env, no *.db — secrets via env)
COPY main.py database.py models.py schemas.py middleware.py limiter.py auth.py billing.py ./
COPY routes ./routes
COPY seed.json ./seed.json
COPY static ./static

# Some hosts (HF Spaces) hardcode 7860; others inject $PORT
ENV PORT=8080
EXPOSE 8080

# honours $PORT; falls back to 8080
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT:-8080}"]
