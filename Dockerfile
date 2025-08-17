## Dockerfile for ComfyUI with custom nodes (converted from Modal image spec in `comfyapp.py`)
## Build (CPU example):
##   docker build -t comfyui-runner .
## Build (GPU example w/ CUDA base):
##   docker build --build-arg BASE_IMAGE=nvidia/cuda:12.8.0-cudnn-runtime-ubuntu22.04 -t comfyui-runner .
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
## Comfy installation (Jupyter disabled)
## JupyterLab support has been temporarily disabled. This block only ensures
## ComfyUI is present (or installs it if missing). If using a provider image
## that already ships ComfyUI, we skip reinstallation.
## ---------------------------------------------------------------------------
ARG ADD_NVIDIA=true
# Enable extra debug output during comfy detection/install (set to 0 to disable)
ARG DEBUG_COMFY=1
RUN set -eux; \
        echo "[Comfy][Debug] Base image: ${BASE_IMAGE}"; \
        echo "[Comfy][Debug] ADD_NVIDIA=${ADD_NVIDIA} DEBUG_COMFY=${DEBUG_COMFY}"; \
        echo "[Comfy][Debug] PATH=$PATH"; \
        echo "[Comfy][Debug] Python: $(command -v python || true)"; \
        python --version || true; \
        if [[ "${DEBUG_COMFY}" == "1" ]]; then \
            echo "[Comfy][Debug] Listing potential bin directories"; \
            for d in /usr/local/bin /usr/bin /root/.local/bin /opt/conda/bin; do \
                [[ -d "$d" ]] && echo "--- $d" && ls -1 "$d" | grep -i comfy || true; \
            done; \
        fi; \
        if ! command -v comfy >/dev/null 2>&1; then \
            echo "[Comfy][Info] 'comfy' not found in base image; installing comfy-cli (Jupyter disabled)"; \
            pip install --no-cache-dir --upgrade pip comfy-cli || { echo "[Comfy][Error] pip install failed" >&2; exit 1; }; \
            hash -r || true; \
            if ! command -v comfy >/dev/null 2>&1; then \
                echo "[Comfy][Warn] 'comfy' still not on PATH after install. Dumping debug info."; \
                python -c 'import sys,sysconfig,os;print("executable=",sys.executable);print("version=",sys.version);import shutil;print("which comfy=",shutil.which("comfy"));print(sysconfig.get_paths())' || true; \
                find / -maxdepth 4 -type f -name 'comfy' 2>/dev/null | head -n 20 || true; \
            fi; \
            if [[ "$ADD_NVIDIA" == "true" ]]; then \
                echo "[Comfy][Info] Running comfy install with NVIDIA flags"; \
                comfy --skip-prompt install --fast-deps --nvidia || { echo "[Comfy][Error] comfy install (nvidia) failed" >&2; exit 1; }; \
            else \
                echo "[Comfy][Info] Running comfy install (CPU)"; \
                comfy --skip-prompt install --fast-deps || { echo "[Comfy][Error] comfy install (cpu) failed" >&2; exit 1; }; \
            fi; \
        else \
            echo "[Comfy][Info] 'comfy' already present; (Jupyter disabled, skipping jupyterlab ensure)"; \
            command -v comfy; \
            comfy --version || true; \
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

EXPOSE 8000
ENTRYPOINT ["docker-entrypoint.sh"]
