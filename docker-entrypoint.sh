#!/usr/bin/env bash
set -euo pipefail

echo "[Entrypoint] Starting container..."
echo "Python version: $(python -V)"
echo "Working dir: $(pwd)"
DEFAULT_MODE=${DEFAULT_MODE:-jupyter}  # jupyter | comfy | both
echo "Startup mode: $DEFAULT_MODE"

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
  echo "[ComfyUI] Preparing launch..."
  # Optional copy of the baked-in /root/comfy install to a user-provided directory (e.g. a mounted volume)
  # Env vars:
  #   COPY_COMFY_TO=/path/for/writable/copy
  #   COPY_COMFY_FORCE=1  (force re-copy even if destination exists)
  COMFY_SOURCE_ROOT="/root/comfy"
  COMFY_ACTIVE_ROOT="$COMFY_SOURCE_ROOT"
  if [[ -n "${COPY_COMFY_TO:-}" ]]; then
    dest="${COPY_COMFY_TO}"
    if [[ "${dest}" == "${COMFY_SOURCE_ROOT}" ]]; then
      echo "[ComfyUI][Copy] Destination same as source; skipping copy.";
    else
      if [[ -d "${dest}/ComfyUI" && -z "${COPY_COMFY_FORCE:-}" ]]; then
        echo "[ComfyUI][Copy] Existing ComfyUI install detected at ${dest}; set COPY_COMFY_FORCE=1 to overwrite.";
      else
        echo "[ComfyUI][Copy] Copying ComfyUI install to ${dest} ...";
        mkdir -p "${dest}";
        # Use rsync if present for speed; fallback to cp -a
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
  export COMFY_ACTIVE_ROOT
  echo "[ComfyUI] Active root: ${COMFY_ACTIVE_ROOT}"
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
