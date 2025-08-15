ComfyUI + Jupyter Runner (Docker)
=================================

This image packages [ComfyUI](https://github.com/comfyanonymous/ComfyUI) with optional runtime installation of extra custom nodes and now includes a Jupyter Notebook server.
It also bundles helpful utilities: `cloudflared` (for optional tunnels) and `rclone` (for syncing models or assets from cloud storage providers).

Quick Start
-----------

CPU run (GitHub Container Registry) - Jupyter only (default mode):

```
docker run -p 8888:8888 ghcr.io/tg-tjmitchell/comfyui-runner:latest

Access Jupyter at: http://localhost:8888

Run ComfyUI only:

```
docker run -e DEFAULT_MODE=comfy -p 8000:8000 ghcr.io/tg-tjmitchell/comfyui-runner:latest
```

Run both Jupyter (8888) and ComfyUI (8000):

```
docker run -e DEFAULT_MODE=both -p 8000:8000 -p 8888:8888 ghcr.io/tg-tjmitchell/comfyui-runner:latest
```

Environment Variables
---------------------

* `DEFAULT_MODE` (`jupyter` | `comfy` | `both`) – selects what to launch. Default: `jupyter`.
* `COMFY_PORT` – ComfyUI port (default 8000)
* `JUPYTER_PORT` – Jupyter port (default 8888)
* `JUPYTER_TOKEN` – Explicit token to require for access (takes precedence over password).
* `JUPYTER_PASSWORD` – Fallback token/password if `JUPYTER_TOKEN` unset (not hashed).
* `JUPYTER_ALLOW_ORIGIN_ALL` – set to `1` to allow any Origin (helpful behind proxies like RunPod / cloudflared).
* `INSTALL_EXTRA_NODES` – extra custom nodes to install at container start (only used when ComfyUI is started)
* `COPY_COMFY_TO` – if set, on launch the baked-in `/root/comfy` tree is copied to this path (e.g. a mounted volume) and the app runs from there. Skips copy if destination already has a `ComfyUI` directory unless `COPY_COMFY_FORCE=1`.
* `COPY_COMFY_FORCE` – set to `1` to force overwriting the destination when using `COPY_COMFY_TO`.
* `RCLONE_DROPBOX_TOKEN_JSON` – full JSON token object for configuring a Dropbox remote (preferred over bare token).
* `RCLONE_DROPBOX_ACCESS_TOKEN` – simple access token (fallback). A minimal JSON is synthesized; may require refresh for long sessions.
```

JupyterLab Only
----------------

This image ships only with JupyterLab (classic Notebook server removed to reduce size).

Extra Nodes at Runtime (ComfyUI)
--------------------------------

Set `INSTALL_EXTRA_NODES` to a space-separated list of repository specs for additional nodes to install right before ComfyUI launch (works in `comfy` or `both` modes):

```
-e INSTALL_EXTRA_NODES="https://github.com/user/some-node.git another-node-repo"
```

License
-------

MIT

Copying ComfyUI Install to a Volume
-----------------------------------

To persist changes (custom nodes, models metadata, etc.) outside the writable layers, you can copy the baked image install to a mounted volume at container start:

```
docker run \
	-e DEFAULT_MODE=comfy \
	-e COPY_COMFY_TO=/data/comfy \
	-v $(pwd)/comfy-data:/data/comfy \
	-p 8000:8000 ghcr.io/tg-tjmitchell/comfyui-runner:latest
```

If `/data/comfy/ComfyUI` already exists, copy is skipped. To force refresh:

```
-e COPY_COMFY_FORCE=1
```

After copying, ComfyUI launches from the destination path. This keeps the original `/root/comfy` pristine and lets you bind-mount persistent storage.

Configuring rclone Dropbox Remote
---------------------------------

Provide one of the environment variables below and the entrypoint will create `/root/.config/rclone/rclone.conf` with a `[dropbox]` remote:

```
-e RCLONE_DROPBOX_TOKEN_JSON='{"access_token":"XXX","token_type":"bearer","refresh_token":"YYY","expiry":"2025-09-01T00:00:00Z"}'
```

or (less complete):

```
-e RCLONE_DROPBOX_ACCESS_TOKEN=sl.BC123...
```

Example: sync a models folder from Dropbox into the mounted models volume (one-shot before launch):

```
docker run \
	-e DEFAULT_MODE=comfy \
	-e RCLONE_DROPBOX_ACCESS_TOKEN=sl.BC123... \
	-e COPY_COMFY_TO=/data/comfy \
	-v $(pwd)/comfy-data:/data/comfy \
	-v $(pwd)/models:/root/comfy/ComfyUI/models \
	--entrypoint bash \
	ghcr.io/tg-tjmitchell/comfyui-runner:latest -lc "rclone sync dropbox:my-comfy-models /root/comfy/ComfyUI/models && docker-entrypoint.sh"
```

(For frequent syncs you could run rclone sidecar or a cron within the container.)
