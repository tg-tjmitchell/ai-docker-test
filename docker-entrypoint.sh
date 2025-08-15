#!/usr/bin/env bash
set -euo pipefail

echo "[Entrypoint] Starting container..."
echo "Python version: $(python -V)"
echo "Working dir: $(pwd)"
DEFAULT_MODE=${DEFAULT_MODE:-jupyter}  # jupyter | comfy | both
echo "Startup mode: $DEFAULT_MODE"

# Prepare (and optionally copy) ComfyUI install regardless of launch mode so
# that Jupyter-only sessions can still explore/modify a writable copy.
prepare_comfy_root() {
  COMFY_SOURCE_ROOT="/root/comfy"
  COMFY_ACTIVE_ROOT="${COMFY_SOURCE_ROOT}"
  if [[ -n "${COPY_COMFY_TO:-}" ]]; then
    local dest="${COPY_COMFY_TO}"
    if [[ "${dest}" == "${COMFY_SOURCE_ROOT}" ]]; then
      echo "[ComfyUI][Copy] Destination equals source (${dest}); skipping copy."
    else
      if [[ -d "${dest}/ComfyUI" && -z "${COPY_COMFY_FORCE:-}" ]]; then
        echo "[ComfyUI][Copy] Existing install at ${dest}; skipping (set COPY_COMFY_FORCE=1 to overwrite)."
      else
        echo "[ComfyUI][Copy] Copying ComfyUI install to ${dest} ..."
        mkdir -p "${dest}"
        if command -v rsync >/dev/null 2>&1; then
          rsync -a --delete "${COMFY_SOURCE_ROOT}/" "${dest}/" || { echo "[ComfyUI][Copy] rsync failed" >&2; exit 1; }
        else
          rm -rf "${dest}/"* 2>/dev/null || true
          cp -a "${COMFY_SOURCE_ROOT}/." "${dest}/" || { echo "[ComfyUI][Copy] cp failed" >&2; exit 1; }
        fi
      fi
      COMFY_ACTIVE_ROOT="${dest}"
    fi
  fi
  export COMFY_ACTIVE_ROOT COMFY_SOURCE_ROOT
  echo "[ComfyUI] Active root prepared: ${COMFY_ACTIVE_ROOT}"
}

prepare_comfy_root

# ---------------------------------------------------------------------------
# Optional rclone Dropbox configuration
# Env vars:
#   RCLONE_DROPBOX_TOKEN_JSON  - full JSON object string for token (preferred)
#   RCLONE_DROPBOX_ACCESS_TOKEN - bare access token (fallback; creates minimal JSON)
# Creates /root/.config/rclone/rclone.conf if provided.
# ---------------------------------------------------------------------------
if [[ -n "${RCLONE_DROPBOX_TOKEN_JSON:-}" || -n "${RCLONE_DROPBOX_ACCESS_TOKEN:-}" ]]; then
  echo "[rclone] Configuring Dropbox remote";
  mkdir -p /root/.config/rclone;
  RCLONE_CONF="/root/.config/rclone/rclone.conf";
  {
    echo "[dropbox]";
    echo "type = dropbox";
    if [[ -n "${RCLONE_DROPBOX_TOKEN_JSON:-}" ]]; then
      # Don't echo full token to stdout; just write to file
      printf 'token = %s\n' "${RCLONE_DROPBOX_TOKEN_JSON}" >> "${RCLONE_CONF}";
    else
      # Minimal JSON; Dropbox may still require refresh in long sessions
      printf 'token = {"access_token":"%s","token_type":"bearer"}\n' "${RCLONE_DROPBOX_ACCESS_TOKEN}" >> "${RCLONE_CONF}";
    fi
  } > /dev/null 2>&1 # avoid leaking token via build logs
  # Re-open file to append sanitized header (the token already written); ensure permissions
  # (We separated to keep token out of logs; directly writing again for structure)
  if [[ ! -s "${RCLONE_CONF}" ]]; then
    # Fallback in case redirection suppressed everything (unlikely)
    echo "[dropbox]" > "${RCLONE_CONF}";
    echo "type = dropbox" >> "${RCLONE_CONF}";
    if [[ -n "${RCLONE_DROPBOX_TOKEN_JSON:-}" ]]; then
      printf 'token = %s\n' "${RCLONE_DROPBOX_TOKEN_JSON}" >> "${RCLONE_CONF}";
    else
      printf 'token = {"access_token":"%s","token_type":"bearer"}\n' "${RCLONE_DROPBOX_ACCESS_TOKEN}" >> "${RCLONE_CONF}";
    fi
  fi
  chmod 600 "${RCLONE_CONF}" || true
  echo "[rclone] Dropbox remote configured at ${RCLONE_CONF}"
fi

start_comfy() {
  echo "[ComfyUI] Launching from: ${COMFY_ACTIVE_ROOT:-/root/comfy}"
  pushd "${COMFY_ACTIVE_ROOT}/ComfyUI" >/dev/null || { echo "[ComfyUI] Could not cd into active ComfyUI directory" >&2; exit 1; }
  if [[ -n "${INSTALL_EXTRA_NODES:-}" ]]; then
    echo "Installing extra nodes at runtime: ${INSTALL_EXTRA_NODES}"
    comfy node install --fast-deps ${INSTALL_EXTRA_NODES} || echo "[Warn] Some runtime node installs failed"
  fi
  CMD_ARGS=("--listen" "0.0.0.0" "--port" "${COMFY_PORT:-8000}")
  echo "Launching: comfy launch -- ${CMD_ARGS[*]}"
  comfy launch -- "${CMD_ARGS[@]}" &
  COMFY_PID=$!
  popd >/dev/null || true
}

start_jupyter() {
  local port="${JUPYTER_PORT:-8888}"
  local token_opt
  local password_opt
  local allow_origin_opt
  if [[ -n "${JUPYTER_TOKEN:-}" ]]; then
    token_opt="--ServerApp.token=${JUPYTER_TOKEN}"
    password_opt="--ServerApp.password="
  elif [[ -n "${JUPYTER_PASSWORD:-}" ]]; then
    token_opt="--ServerApp.token=${JUPYTER_PASSWORD}"
    password_opt="--ServerApp.password="
  else
    token_opt="--ServerApp.token="
    password_opt="--ServerApp.password="
  fi
  if [[ "${JUPYTER_ALLOW_ORIGIN_ALL:-}" == "1" ]]; then
    allow_origin_opt="--ServerApp.allow_origin=*"
  else
    allow_origin_opt=""
  fi
  echo "[Jupyter] Launching JupyterLab on 0.0.0.0:${port} (origin_all=${JUPYTER_ALLOW_ORIGIN_ALL:-0})"
  jupyter lab \
    --ip=0.0.0.0 \
    --port="${port}" \
    --no-browser \
    --allow-root \
    ${token_opt} \
    ${password_opt} \
    ${allow_origin_opt} &
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
