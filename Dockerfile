## Dockerfile for ComfyUI with custom nodes (converted from Modal image spec in `comfyapp.py`)
## Build (CPU example):
##   docker build -t comfyui-runner .
## Build (GPU example w/ CUDA base):
##   docker build --build-arg BASE_IMAGE=nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04 -t comfyui-runner .
## Run (CPU):
##   docker run -p 8000:8000 comfyui-runner
## Run (GPU w/ NVIDIA Container Toolkit):
##   docker run --gpus all -p 8000:8000 comfyui-runner

ARG BASE_IMAGE=python:3.11-slim
FROM ${BASE_IMAGE} as base

LABEL org.opencontainers.image.title="ComfyUI Runner" \
    org.opencontainers.image.source="https://github.com/tg-tjmitchell/comfyui-modal-runner" \
    org.opencontainers.image.description="Containerized ComfyUI with plugin installation mirrored from Modal setup" \
    org.opencontainers.image.licenses="MIT"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    COMFY_PORT=8000 \
    JUPYTER_PORT=8888 \
    DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-lc"]

# ---------------------------------------------------------------------------
# System dependencies (mirrors apt installs in comfyapp.py)
# ---------------------------------------------------------------------------
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends git ffmpeg wget ca-certificates python3-dev build-essential libgl1 curl rclone; \
    rm -rf /var/lib/apt/lists/*

## ---------------------------------------------------------------------------
## Comfy / Jupyter installation (conditional)
## This block is now resilient to using a provider image that already ships
## with ComfyUI (e.g. vastai/comfy:* or runpod/comfyui:*). If the "comfy"
## executable is present we skip reinstalling core and only ensure jupyterlab.
## For custom / neutral bases (nvidia/cuda, runpod/pytorch, python:*-slim) it
## performs a full comfy-cli driven install.
## ---------------------------------------------------------------------------
ARG ADD_NVIDIA=true
RUN set -eux; \
    if ! command -v comfy >/dev/null 2>&1; then \
    echo "Comfy not found in base image; installing comfy-cli & JupyterLab"; \
    pip install --no-cache-dir --upgrade pip comfy-cli jupyterlab; \
    if [[ "$ADD_NVIDIA" == "true" ]]; then \
    comfy --skip-prompt install --fast-deps --nvidia; \
    else \
    comfy --skip-prompt install --fast-deps; \
    fi; \
    else \
    echo "Comfy already present; ensuring JupyterLab is available"; \
    python -c 'import jupyterlab' 2>/dev/null || pip install --no-cache-dir jupyterlab; \
    fi

# Cloudflared (optional; mirrors Modal image). Fail gracefully if deps missing.
RUN set -eux; \
    wget -O /tmp/cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb; \
    apt-get update; \
    (apt-get install -y /tmp/cloudflared.deb || (dpkg -i /tmp/cloudflared.deb && apt-get install -f -y)) || echo "cloudflared install skipped"; \
    rm -f /tmp/cloudflared.deb; \
    rm -rf /var/lib/apt/lists/*

# (Comfy core already handled above conditionally)

# ---------------------------------------------------------------------------
# Copy project files (only those needed at build time for install/config)
# ---------------------------------------------------------------------------
WORKDIR /workspace
COPY plugins.csv config.ini ./

# ---------------------------------------------------------------------------
# Install custom nodes from first row of plugins.csv (comma separated)
# Mirrors logic in comfyapp.py (get_nodes_from_csv)
# ---------------------------------------------------------------------------
RUN set -eux; \
    if [[ -f plugins.csv ]]; then \
    nodes_line=$(head -n1 plugins.csv || true); \
    if [[ -n "$nodes_line" ]]; then \
    nodes=$(echo "$nodes_line" | tr ',' ' '); \
    echo "Installing custom nodes: $nodes"; \
    comfy node install --fast-deps $nodes || echo "Some node installs failed"; \
    else \
    echo "plugins.csv empty; skipping node install"; \
    fi; \
    fi

# ---------------------------------------------------------------------------
# Place config files where Modal image placed them
# ---------------------------------------------------------------------------
RUN set -eux; \
    mkdir -p /root/comfy/ComfyUI/user/default/ComfyUI-Manager; \
    mkdir -p /root/comfy/ComfyUI/custom_nodes/comfyui-lora-manager; \
    mkdir -p /root/comfy/ComfyUI/temp; \
    if [[ -f config.ini ]]; then \
    cp config.ini /root/comfy/ComfyUI/user/default/ComfyUI-Manager/config.ini; \
    fi
# (workflow_api.json no longer used)

# Reset models directory (will be a volume) like Modal build
RUN rm -rf /root/comfy/ComfyUI/models && mkdir -p /root/comfy/ComfyUI/models

VOLUME ["/root/comfy/ComfyUI/models"]

HEALTHCHECK --interval=30s --timeout=5s --retries=5 CMD curl -fs http://127.0.0.1:${COMFY_PORT}/ || exit 1

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 8000 8888
ENTRYPOINT ["docker-entrypoint.sh"]
