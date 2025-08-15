ComfyUI + Jupyter Runner (Docker)
=================================

This image packages [ComfyUI](https://github.com/comfyanonymous/ComfyUI) with optional runtime installation of extra custom nodes and now includes a Jupyter Notebook server.

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
* `INSTALL_EXTRA_NODES` – extra custom nodes to install at container start (only used when ComfyUI is started)
```

Extra Nodes at Runtime (ComfyUI)
--------------------------------

Set `INSTALL_EXTRA_NODES` to a space-separated list of repository specs for additional nodes to install right before ComfyUI launch (works in `comfy` or `both` modes):

```
-e INSTALL_EXTRA_NODES="https://github.com/user/some-node.git another-node-repo"
```

License
-------

MIT
