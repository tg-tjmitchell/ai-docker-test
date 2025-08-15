#!/usr/bin/env bash
set -euo pipefail

echo "[Entrypoint] Starting ComfyUI..."
echo "Python version: $(python -V)"
echo "ComfyUI directory: /root/comfy/ComfyUI"

if [[ -n "${INSTALL_EXTRA_NODES:-}" ]]; then
  echo "Installing extra nodes at runtime: ${INSTALL_EXTRA_NODES}"
  comfy node install --fast-deps ${INSTALL_EXTRA_NODES} || echo "[Warn] Some runtime node installs failed"
fi


CMD_ARGS=("--listen" "0.0.0.0" "--port" "${COMFY_PORT:-8000}")
echo "Launching: comfy launch -- ${CMD_ARGS[*]}"
exec comfy launch -- "${CMD_ARGS[@]}"
