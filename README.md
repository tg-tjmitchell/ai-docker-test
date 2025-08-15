ComfyUI Runner (Docker)
=======================

This image packages [ComfyUI](https://github.com/comfyanonymous/ComfyUI) with optional runtime installation of extra custom nodes.

Quick Start
-----------

CPU run:

```
docker run -p 8000:8000 tg-tjmitchell/comfyui-runner:latest
```

Extra Nodes at Runtime
----------------------

Set `INSTALL_EXTRA_NODES` to a space-separated list of repository specs for additional nodes to install right before launch:

```
-e INSTALL_EXTRA_NODES="https://github.com/user/some-node.git another-node-repo"
```

License
-------

MIT
