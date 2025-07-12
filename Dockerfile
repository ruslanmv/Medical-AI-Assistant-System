# ------------------------------------------------------------------
# Dockerfile — Medical AI Assistant System
#
# • Runs the MCP server (STDIO by default; HTTP-ready if you modify
#   server.py to bind 0.0.0.0:8000).
# • Uses python:3.11-slim for a small footprint.
# • Installs only build essentials, drops root, and copies project.
# • Pass your watsonx credentials at runtime via --env-file .env.
# ------------------------------------------------------------------

# syntax=docker/dockerfile:1
FROM python:3.11-slim AS base

LABEL org.opencontainers.image.title="Medical AI Assistant System" \
      org.opencontainers.image.description="Multi-agent medical assistant powered by IBM watsonx.ai" \
      org.opencontainers.image.licenses="Apache-2.0" \
      maintainer="ruslanmv"

# ------------------------------------------------------------
# Build-time dependencies (minimal)
# ------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential gcc git curl && \
    rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------
# Non-root user for security
# ------------------------------------------------------------
ARG APP_USER=app
ARG APP_UID=1000
RUN adduser --disabled-password --gecos "" --uid ${APP_UID} ${APP_USER}

WORKDIR /app

# ------------------------------------------------------------
# Python dependencies
# ------------------------------------------------------------
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# ------------------------------------------------------------
# Copy project files
# ------------------------------------------------------------
COPY . .

# ------------------------------------------------------------
# Environment
# ------------------------------------------------------------
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

USER ${APP_USER}

# ------------------------------------------------------------
# Ports (optional HTTP mode) & entrypoint
# ------------------------------------------------------------
EXPOSE 8000
ENTRYPOINT ["python", "server.py"]
