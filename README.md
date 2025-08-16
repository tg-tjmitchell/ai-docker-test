ComfyUI Runner (Docker)
=======================

Jupyter support has been temporarily disabled. This image packages [ComfyUI](https://github.com/comfyanonymous/ComfyUI) with optional runtime installation of extra custom nodes. It also bundles helpful utilities: `cloudflared` (for optional tunnels) and `rclone` (for syncing models or assets from cloud storage providers).

Quick Start
-----------

Quick run:

```
docker run -p 8000:8000 ghcr.io/tg-tjmitchell/comfyui-runner:latest
```

Environment Variables
---------------------

* `DEFAULT_MODE` (`comfy`) – Only `comfy` is active (Jupyter disabled). Default: `comfy`.
* `COMFY_PORT` – ComfyUI port (default 8000)
* `INSTALL_EXTRA_NODES` – extra custom nodes to install at container start (only used when ComfyUI is started)
* `COPY_COMFY_TO` – if set, at container startup (regardless of mode) the baked-in `/root/comfy` tree is copied to this path (e.g. a mounted volume) and subsequent ComfyUI launches (now or later) run from there. Skips copy if destination already has a `ComfyUI` directory unless `COPY_COMFY_FORCE=1`.
* `COPY_COMFY_FORCE` – set to `1` to force overwriting the destination when using `COPY_COMFY_TO`.
* `RCLONE_DROPBOX_TOKEN_JSON` – full JSON token object for configuring a Dropbox remote (preferred over bare token).
* `RCLONE_DROPBOX_ACCESS_TOKEN` – simple access token (fallback). A minimal JSON is synthesized; may require refresh for long sessions.
```

JupyterLab
----------

Previously this image exposed a JupyterLab server. That layer has been removed for now; attempts to set `DEFAULT_MODE=jupyter` (or `both`) will log a warning and only start ComfyUI. A future solution may reintroduce a notebook workflow via a different mechanism.

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

Build Matrix / Variants
-----------------------

This repo now includes a `docker-bake.hcl` so you can efficiently build multiple image variants from the single `Dockerfile`:

Variants:

* `core` (tag: `:core`) – Provider-neutral GPU image based on `nvidia/cuda:12.1.1-cudnn-runtime-ubuntu22.04`.
* `vast` (tag: `:vast`) – Uses `vastai/comfy:cuda12.1-ubuntu22.04` to minimize startup work on Vast.ai hosts.
* `runpod` (tag: `:runpod`) – Uses `runpod/comfyui:cuda12.1` for minimal work on RunPod.
* `cpu` (tag: `:cpu`) – CPU/testing variant from `python:3.11-slim` with `ADD_NVIDIA=false`.

Each variant only adds your custom nodes/config layers; provider images that already ship ComfyUI skip a redundant install thanks to a conditional in the `Dockerfile`.

docker buildx bake usage examples:

```
# Build neutral core variant (local)
docker buildx bake neutral

# Build Vast.ai + RunPod optimized variants together
docker buildx bake vast runpod

# Build all variants
docker buildx bake all

# Build & push (after login) to the configured IMAGE_REPO
docker buildx bake all --push

# Override image repo / version on the fly
docker buildx bake neutral --set *.args.IMAGE_REPO=ghcr.io/your/repo --set *.args.VERSION=0.1.0
```

Makefile shortcuts (optional):

```
make neutral            # builds :core variant
make vast runpod cpu    # builds each respectively
make all                # builds every target
make push               # builds & pushes all variants
```

Caching: Use registry cache to accelerate CI incremental builds:

```
docker buildx bake all \
	--set *.cache-from=type=registry,ref=ghcr.io/you/comfyui-runner:buildcache \
	--set *.cache-to=type=registry,ref=ghcr.io/you/comfyui-runner:buildcache,mode=max
```

Digest pinning: For reproducibility you can replace tag strings in `docker-bake.hcl` with immutable digests (`image@sha256:...`).

Why a bake file? It centralizes variant definitions so CI or local commands build a consistent matrix without duplicating Dockerfiles; `buildx bake` also schedules builds in parallel where possible and shares cached layers among targets.
