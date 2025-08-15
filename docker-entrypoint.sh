#!/usr/bin/env bash
set -euo pipefail

echo "[Entrypoint] Starting container..."
echo "Python version: $(python -V)"
echo "Working dir: $(pwd)"
DEFAULT_MODE=${DEFAULT_MODE:-jupyter}  # jupyter | comfy | both
echo "Startup mode: $DEFAULT_MODE"

start_comfy() {
  echo "[ComfyUI] Preparing launch..."
  if [[ -n "${INSTALL_EXTRA_NODES:-}" ]]; then
    echo "Installing extra nodes at runtime: ${INSTALL_EXTRA_NODES}"
    comfy node install --fast-deps ${INSTALL_EXTRA_NODES} || echo "[Warn] Some runtime node installs failed"
  fi
  CMD_ARGS=("--listen" "0.0.0.0" "--port" "${COMFY_PORT:-8000}")
  echo "Launching: comfy launch -- ${CMD_ARGS[*]}"
  comfy launch -- "${CMD_ARGS[@]}" &
  COMFY_PID=$!
}

start_jupyter() {
  echo "[Jupyter] Launching notebook server on 0.0.0.0:${JUPYTER_PORT:-8888}";
  # Generate config if not present (disable token & allow root for ease inside container)
  jupyter notebook \
    --ip=0.0.0.0 \
    --port="${JUPYTER_PORT:-8888}" \
    --no-browser \
    --NotebookApp.token='' \
    --NotebookApp.password='' \
    --allow-root &
  JUPYTER_PID=$!
}

case "$DEFAULT_MODE" in
  jupyter)
    start_jupyter
    wait $JUPYTER_PID
    ;;
  comfy)
    start_comfy
    wait $COMFY_PID
    ;;
  both)
    start_comfy
    start_jupyter
    # Wait on both processes; exit if either terminates
    wait -n $COMFY_PID $JUPYTER_PID
    ;;
  *)
    echo "Unknown DEFAULT_MODE '$DEFAULT_MODE' (expected jupyter|comfy|both)" >&2
    exit 1
    ;;
esac
