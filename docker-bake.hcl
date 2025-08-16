// docker-bake.hcl
// Multi-variant build matrix for ComfyUI runner:
//   neutral : Provider-agnostic (CUDA runtime base) – push this for general use
//   vast    : Vast.ai optimized (uses vastai/comfy base w/ ComfyUI preinstalled)
//   runpod  : RunPod optimized (uses runpod/comfyui base)
//   cpu     : CPU / CI / local minimal testing (no GPU libs)
//
// Usage:
//   docker buildx bake                 # build default group (neutral, vast, runpod, cpu)
//   docker buildx bake vast runpod     # build selected targets
//   docker buildx bake --push          # build & push (needs registry auth)
//   docker buildx bake neutral --load  # load single image into local docker
//
// Override examples:
//   docker buildx bake --set *.args.ADD_NVIDIA=true
//   docker buildx bake --set neutral.args.BASE_IMAGE=nvidia/cuda:12.2.2-cudnn-runtime-ubuntu22.04 neutral
//   docker buildx bake --set neutral.tags="ghcr.io/me/comfyui:core-v1"
//
// Caching (recommended for CI speedups):
//   docker buildx bake --set *.cache-from=type=registry,ref=$IMAGE_REPO:buildcache \
//                      --set *.cache-to=type=registry,ref=$IMAGE_REPO:buildcache,mode=max
//
// Digest pinning (production): after testing, run `docker buildx imagetools inspect <tag>` and
// replace BASE_IMAGE tags with immutable @sha256:<digest> values.

variable "IMAGE_REPO" { default = "ghcr.io/tg-tjmitchell/comfyui-runner" }
variable "VERSION"    { default = "latest" }
variable "PLATFORM"   { default = "linux/amd64" }
variable "ADD_NVIDIA" { default = "true" }

// Default group
group "default" { targets = ["neutral", "vast", "runpod", "cpu"] }

// Base target template
target "_base" {
  context    = "."
  dockerfile = "Dockerfile"
  platforms  = [var.PLATFORM]
  args = {
    ADD_NVIDIA = ADD_NVIDIA
  }
  labels = {
    "org.opencontainers.image.source" = "https://github.com/tg-tjmitchell/ai-docker-test"
  }
}

// Provider-neutral GPU image
target "neutral" {
  inherits = ["_base"]
  args = { BASE_IMAGE = "nvidia/cuda:12.1.1-cudnn-runtime-ubuntu22.04" }
  tags = ["${IMAGE_REPO}:core", "${IMAGE_REPO}:core-${VERSION}", "${IMAGE_REPO}:neutral-${VERSION}"]
}

// Vast.ai optimized
target "vast" {
  inherits = ["_base"]
  args = { BASE_IMAGE = "vastai/comfy:cuda12.1-ubuntu22.04" }
  tags = ["${IMAGE_REPO}:vast", "${IMAGE_REPO}:vast-${VERSION}"]
}

// RunPod optimized
target "runpod" {
  inherits = ["_base"]
  args = { BASE_IMAGE = "runpod/comfyui:cuda12.1" }
  tags = ["${IMAGE_REPO}:runpod", "${IMAGE_REPO}:runpod-${VERSION}"]
}

// CPU / test variant
target "cpu" {
  inherits = ["_base"]
  args = {
    BASE_IMAGE  = "python:3.11-slim"
    ADD_NVIDIA  = "false"
  }
  tags = ["${IMAGE_REPO}:cpu", "${IMAGE_REPO}:cpu-${VERSION}"]
}
