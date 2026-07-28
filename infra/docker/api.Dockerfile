FROM python:3.11-slim

WORKDIR /app

# 1) Fix apt sources to use HTTPS (to avoid http:80 timeouts) + install deps in one layer
RUN set -eux; \
    sed -i 's|http://deb.debian.org|https://deb.debian.org|g' /etc/apt/sources.list.d/debian.sources || true; \
    sed -i 's|http://deb.debian.org|https://deb.debian.org|g' /etc/apt/sources.list || true; \
    apt-get -o Acquire::Retries=5 update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        libpq-dev \
        ca-certificates \
    ; \
    rm -rf /var/lib/apt/lists/*

# 2) Add Supabase Root CA (file MUST be valid PEM)
COPY infra/certs/prod-ca-2021.crt /usr/local/share/ca-certificates/supabase_root_2021_ca.crt
RUN update-ca-certificates

COPY services/api/backend /app/backend
COPY services/api/pyproject.toml /app/pyproject.toml

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN python -m pip install --upgrade pip && python -m pip install .

RUN addgroup --system app && adduser --system --ingroup app app && chown -R app:app /app
USER app

CMD ["uvicorn", "backend.apps.api.main:app", "--host", "0.0.0.0", "--port", "8001"]
