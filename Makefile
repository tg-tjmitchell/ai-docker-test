# Makefile shortcuts for building/pushing ComfyUI runner variants
# Requires: docker buildx (docker >= 20.10) and a builder instance supporting multi-arch if desired.

IMAGE_REPO ?= ghcr.io/tg-tjmitchell/comfyui-runner
VERSION    ?= latest

# Initialize a buildx builder (idempotent)
.PHONY: builder
builder:
	@if ! docker buildx inspect comfy-builder >/dev/null 2>&1; then \
		docker buildx create --name comfy-builder --use; \
	fi

.PHONY: neutral vast runpod cpu all
neutral vast runpod cpu: builder
	docker buildx bake $@ --set *.args.VERSION=$(VERSION) --set *.args.IMAGE_REPO=$(IMAGE_REPO)

all: builder
	docker buildx bake all --set *.args.VERSION=$(VERSION) --set *.args.IMAGE_REPO=$(IMAGE_REPO)

# Push all variants (login first)
.PHONY: push
push: builder
	docker buildx bake all --push --set *.args.VERSION=$(VERSION) --set *.args.IMAGE_REPO=$(IMAGE_REPO)

# Use registry cache to accelerate rebuilds (requires a ref for cache)
CACHE_REF ?= $(IMAGE_REPO):buildcache
.PHONY: push-cache
push-cache: builder
	docker buildx bake all --push \
		--set *.cache-from=type=registry,ref=$(CACHE_REF) \
		--set *.cache-to=type=registry,ref=$(CACHE_REF),mode=max \
		--set *.args.VERSION=$(VERSION) --set *.args.IMAGE_REPO=$(IMAGE_REPO)

# Clean builder (won't remove images in registry)
.PHONY: clean-builder
clean-builder:
	-docker buildx rm comfy-builder
