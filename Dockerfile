# DOCKERFILE anteriormente INSEGURO (VIOLAÇÃO DOS 4 MANDAMENTOS DO HARDENING)
# 1. Não usa multi-stage build (imagem pesada) -> criado multi-stage build (imagem mais leve e menos vulnerável)
# 2. Usa tag :latest mutável -> atualizado para python:3.11-slim (imagem leve)
# 3. Executa como ROOT por padrão -> usa usuário não-root (nonroot)
# 4. Sem declaração de HEALTHCHECK -> adicionado HEALTHCHECK

# Build Stage
FROM python:3.11-slim AS builder

WORKDIR /app

# Instala pacotes
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential=12.12 \
    && rm -rf /var/lib/apt/lists/*

# Ambiente virtual
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Correção de CVE-2026-23949 e CVE-2026-24049
RUN pip install --no-cache-dir --upgrade "setuptools==82.0.1"

# Copia e instala as dependências
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Runtime Stage
FROM python:3.11-slim

WORKDIR /app

# Atualiza o sistema e remove cache do apt para economizar espaço
RUN apt-get update && apt-get upgrade -y \
    && rm -rf /var/lib/apt/lists/*

# Correção de CVE-2026-23949 e CVE-2026-24049
RUN pip install --no-cache-dir --upgrade "setuptools==82.0.1"

# Criação do grupo e usuário não-root
RUN groupadd -g 10001 nonroot && \
    useradd --uid 10001 --gid nonroot --no-create-home --shell /usr/sbin/nologin nonroot

# Copia apenas o ambiente virtual do estágio anterior
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copia os arquivos da aplicação definindo como dono o usuário nonroot
COPY --chown=nonroot:nonroot . .

# Cria a pasta do SQLite caso não exista e cofigura as permissões
RUN mkdir -p /app/instance && \
    chown -R nonroot:nonroot /app && \
    chmod -R 755 /app/instance

# Altera para o usuário não-root
USER nonroot

EXPOSE 8080

# Healthcheck
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health', timeout=3).read()"

ENTRYPOINT ["gunicorn", "--bind", "0.0.0.0:8080", "app:create_app()"]
