DOCKER_IMAGE_NAME = calaos-os-builder
DOCKER_TAG ?= latest
DOCKER_COMMAND = docker run -t -v $(PWD):/src --rm -w /src --privileged=true

PKGVERSION :=

print_green = /bin/echo -e "\x1b[32m$1\x1b[0m"

NOCACHE?=0

ifeq ($(NOCACHE),1)
_NOCACHE=true
else
_NOCACHE=false
endif

all:
	$(info )
	@$(call print_green,"Available commands :")
	@$(call print_green,"====================")	
	@ echo
	@ echo "  make                          # Print this help"
	@ echo "  make docker-init              # Build docker image, also build after any changes in Dockerfile"
	@ echo "  make docker-shell             # Run docker container and jump into"
	@ echo "  make docker-rm                # Remove a previous build docker image"
	@ echo "  make build-|calaos-ddns|calaos-home|calaos-server|calaos-meta|grafana|... # Build Arch package"
	@ echo
	@$(call print_green,"Variables values    :")
	@$(call print_green,"=====================")
	@$(call print_green,"example : make calaos-os NOCACHE=0")
	@ echo
	@ echo "NOCACHE = ${NOCACHE}            # Set to 0 if you want to accelerate Docker image build by using cache. default value NOCACHE=1. "
	@ echo

docker-init: Dockerfile
	@$(call print_green,"Building docker image")
	@docker build --no-cache=$(_NOCACHE) -t $(DOCKER_IMAGE_NAME):$(DOCKER_TAG) -f Dockerfile .

docker-shell: docker-init
	@$(DOCKER_COMMAND) -it $(DOCKER_IMAGE_NAME):$(DOCKER_TAG) /bin/bash

docker-rm:
	@docker image rm $(DOCKER_IMAGE_NAME):$(DOCKER_TAG)

build-%: docker-init
	@$(call print_green,"Building $* PKGVERSION=$(PKGVERSION)")
	@$(DOCKER_COMMAND) -v .:/work $(DOCKER_IMAGE_NAME):$(DOCKER_TAG) /build_deb "$*" "$(PKGVERSION)"
