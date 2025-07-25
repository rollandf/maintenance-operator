# Version information
include make/license.mk
include Makefile.version

# VERSION defines the project version for the bundle.
# Update this value when you upgrade the version of your project.
# To re-generate a bundle for another specific version without changing the standard setup, you can:
# - use the VERSION as arg of the bundle target (e.g make bundle VERSION=0.0.2)
# - use environment variables to overwrite this value (e.g export VERSION=0.0.2)
# VERSION ?= 0.0.1

# CHANNELS define the bundle channels used in the bundle.
# Add a new line here if you would like to change its default config. (E.g CHANNELS = "candidate,fast,stable")
# To re-generate a bundle for other specific channels without changing the standard setup, you can:
# - use the CHANNELS as arg of the bundle target (e.g make bundle CHANNELS=candidate,fast,stable)
# - use environment variables to overwrite this value (e.g export CHANNELS="candidate,fast,stable")
ifneq ($(origin CHANNELS), undefined)
BUNDLE_CHANNELS := --channels=$(CHANNELS)
endif

# DEFAULT_CHANNEL defines the default channel used in the bundle.
# Add a new line here if you would like to change its default config. (E.g DEFAULT_CHANNEL = "stable")
# To re-generate a bundle for any other default channel without changing the default setup, you can:
# - use the DEFAULT_CHANNEL as arg of the bundle target (e.g make bundle DEFAULT_CHANNEL=stable)
# - use environment variables to overwrite this value (e.g export DEFAULT_CHANNEL="stable")
ifneq ($(origin DEFAULT_CHANNEL), undefined)
BUNDLE_DEFAULT_CHANNEL := --default-channel=$(DEFAULT_CHANNEL)
endif
BUNDLE_METADATA_OPTS ?= $(BUNDLE_CHANNELS) $(BUNDLE_DEFAULT_CHANNEL)

# IMAGE_TAG_BASE defines the docker.io namespace and part of the image name for remote images.
# This variable is used to construct full image tags for bundle and catalog images.
#
# For example, running 'make bundle-build bundle-push catalog-build catalog-push' will build and push both
# nvidia.com/maintenance-operator-bundle:$VERSION and nvidia.com/maintenance-operator-catalog:$VERSION.
IMAGE_TAG_BASE ?= nvidia.com/maintenance-operator

# BUNDLE_IMG defines the image:tag used for the bundle.
# You can use it as an arg. (E.g make bundle-build BUNDLE_IMG=<some-registry>/<project-name-bundle>:<tag>)
BUNDLE_IMG ?= $(IMAGE_TAG_BASE)-bundle:v$(VERSION)

# BUNDLE_GEN_FLAGS are the flags passed to the operator-sdk generate bundle command
BUNDLE_GEN_FLAGS ?= -q --overwrite --version $(VERSION) $(BUNDLE_METADATA_OPTS)

# USE_IMAGE_DIGESTS defines if images are resolved via tags or digests
# You can enable this value if you would like to use SHA Based Digests
# To enable set flag to true
USE_IMAGE_DIGESTS ?= false
ifeq ($(USE_IMAGE_DIGESTS), true)
	BUNDLE_GEN_FLAGS += --use-image-digests
endif

BUNDLE_OCP_VERSIONS=v4.14

# Set the Operator SDK version to use. By default, what is installed on the system is used.
# This is useful for CI or a project to utilize a specific version of the operator-sdk toolkit.
OPERATOR_SDK_VERSION ?= v1.38.0

# Image URL to use all building/pushing image targets
TAG ?= latest
IMG ?= $(IMAGE_TAG_BASE):$(TAG)
# ENVTEST_K8S_VERSION refers to the version of kubebuilder assets to be downloaded by envtest binary.
ENVTEST_K8S_VERSION = 1.32.0

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

# CONTAINER_TOOL defines the container tool to be used for building images.
# Be aware that the target commands are only tested with Docker which is
# scaffolded by default. However, you might want to replace it to use other
# tools. (i.e. podman)
CONTAINER_TOOL ?= docker

# Setting SHELL to bash allows bash commands to be executed by recipes.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

# Build Args
TARGETOS ?= $(shell go env GOOS)
TARGETARCH ?= $(shell go env GOARCH)
GO_BUILD_OPTS ?= CGO_ENABLED=0 GOOS=$(TARGETOS) GOARCH=$(TARGETARCH)
GO_LDFLAGS ?= $(VERSION_LDFLAGS)
GO_GCFLAGS ?=

# PKGs to test
PKGS = $$(go list ./... | grep -v "/test*" | grep -v ".*/mocks")

# Coverage
COVER_MODE = atomic
COVER_PROFILE = cover.out
LCOV_PATH = lcov.info

## Location to install dependencies to
LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

## Location for build binaries
BUILDDIR ?= $(shell pwd)/build
$(BUILDDIR):
	mkdir -p $(BUILDDIR)

##@ Binary Dependencies download
MOCKERY ?= $(LOCALBIN)/mockery
MOCKERY_VERSION ?= v2.44.2
.PHONY: mockery
mockery: $(MOCKERY) ## Download mockery locally if necessary.
$(MOCKERY): | $(LOCALBIN)
	GOBIN=$(LOCALBIN) go install github.com/vektra/mockery/v2@$(MOCKERY_VERSION)

.PHONY: kustomize
KUSTOMIZE ?= $(LOCALBIN)/kustomize
KUSTOMIZE_VERSION ?= v5.5.0
kustomize: $(KUSTOMIZE) ## Download kustomize locally if necessary. If wrong version is installed, it will be removed before downloading.
$(KUSTOMIZE): $(LOCALBIN)
	@if test -x $(LOCALBIN)/kustomize && ! $(LOCALBIN)/kustomize version | grep -q $(KUSTOMIZE_VERSION); then \
		echo "$(LOCALBIN)/kustomize version is not expected $(KUSTOMIZE_VERSION). Removing it before installing."; \
		rm -rf $(LOCALBIN)/kustomize; \
	fi
	test -s $(LOCALBIN)/kustomize || GOBIN=$(LOCALBIN) go install sigs.k8s.io/kustomize/kustomize/v5@$(KUSTOMIZE_VERSION)

.PHONY: controller-gen
CONTROLLER_GEN ?= $(LOCALBIN)/controller-gen
CONTROLLER_TOOLS_VERSION ?= v0.16.5
controller-gen: $(CONTROLLER_GEN) ## Download controller-gen locally if necessary. If wrong version is installed, it will be overwritten.
$(CONTROLLER_GEN): $(LOCALBIN)
	test -s $(LOCALBIN)/controller-gen && $(LOCALBIN)/controller-gen --version | grep -q $(CONTROLLER_TOOLS_VERSION) || \
	GOBIN=$(LOCALBIN) go install sigs.k8s.io/controller-tools/cmd/controller-gen@$(CONTROLLER_TOOLS_VERSION)

.PHONY: envtest
ENVTEST ?= $(LOCALBIN)/setup-envtest
ENVTEST_VERSION ?= latest
envtest: $(ENVTEST) ## Download envtest-setup locally if necessary.
$(ENVTEST): $(LOCALBIN)
	test -s $(LOCALBIN)/setup-envtest || GOBIN=$(LOCALBIN) go install sigs.k8s.io/controller-runtime/tools/setup-envtest@$(ENVTEST_VERSION)

.PHONY: operator-sdk
OPERATOR_SDK ?= $(LOCALBIN)/operator-sdk
operator-sdk: ## Download operator-sdk locally if necessary.
ifeq (,$(wildcard $(OPERATOR_SDK)))
ifeq (, $(shell which operator-sdk 2>/dev/null))
	@{ \
	set -e ;\
	mkdir -p $(dir $(OPERATOR_SDK)) ;\
	curl -sSLo $(OPERATOR_SDK) https://github.com/operator-framework/operator-sdk/releases/download/$(OPERATOR_SDK_VERSION)/operator-sdk_$(TARGETOS)_$(TARGETARCH) ;\
	chmod +x $(OPERATOR_SDK) ;\
	}
else
OPERATOR_SDK = $(shell which operator-sdk)
endif
endif

.PHONY: opm
OPM = $(LOCALBIN)/opm
opm: ## Download opm locally if necessary.
ifeq (,$(wildcard $(OPM)))
ifeq (,$(shell which opm 2>/dev/null))
	@{ \
	set -e ;\
	mkdir -p $(dir $(OPM)) ;\
	curl -sSLo $(OPM) https://github.com/operator-framework/operator-registry/releases/download/v1.23.0/$(TARGETOS)-$(TARGETARCH)-opm ;\
	chmod +x $(OPM) ;\
	}
else
OPM = $(shell which opm)
endif
endif

SKAFFOLD_VER := v2.16.1
SKAFFOLD := $(abspath $(LOCALBIN)/skaffold-$(SKAFFOLD_VER))
.PHONY: skaffold
skaffold: $(SKAFFOLD) ## Download skaffold locally if necessary.
$(SKAFFOLD): | $(LOCALBIN)
	@{ \
		set -e;\
		curl -fsSL https://storage.googleapis.com/skaffold/releases/$(SKAFFOLD_VER)/skaffold-$(TARGETOS)-$(TARGETARCH) -o $(SKAFFOLD); \
		chmod +x $(SKAFFOLD);\
	}

# kind is used to set-up local kubernetes cluster for e2e tests.
KIND_VER := v0.29.0
KIND := $(abspath $(LOCALBIN)/kind-$(KIND_VER))
.PHONY: kind ## Download kind locally if necessary.
kind: $(KIND)
$(KIND): | $(LOCALBIN)
	@{ \
		set -e; \
		test -s $(LOCALBIN)/$(KIND) || GOBIN=$(LOCALBIN) go install sigs.k8s.io/kind@$(KIND_VER); \
		mv $(LOCALBIN)/kind $(KIND); \
	}

KUBECTL_VER := v1.33.2
KUBECTL := $(abspath $(LOCALBIN)/kubectl-$(KUBECTL_VER))
.PHONY: kubectl ## Download kubectl locally if necessary.
kubectl: $(KUBECTL)
$(KUBECTL): | $(LOCALBIN)
	@{ \
		set -e;\
		curl -fsSL https://dl.k8s.io/release/$(KUBECTL_VER)/bin/$(TARGETOS)/$(TARGETARCH)/kubectl -o $(KUBECTL); \
		chmod +x $(KUBECTL);\
	}

HELM := $(abspath $(LOCALBIN)/helm)
.PHONY: helm
helm: $(HELM) ## Download helm (last release) locally if necessary.
$(HELM): | $(LOCALBIN)
	@{ \
		curl -fsSL -o $(LOCALBIN)/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && \
		chmod 700 $(LOCALBIN)/get_helm.sh && \
		HELM_INSTALL_DIR=$(LOCALBIN) USE_SUDO=false $(LOCALBIN)/get_helm.sh && \
		rm -f $(LOCALBIN)/get_helm.sh; \
	}

YQ := $(abspath $(LOCALBIN)/yq)
YQ_VERSION=v4.44.1
.PHONY: yq
yq: $(YQ) ## Download yq locally if necessary.
$(YQ): | $(LOCALBIN)
	@curl -fsSL -o $(YQ) https://github.com/mikefarah/yq/releases/download/$(YQ_VERSION)/yq_linux_amd64 && chmod +x $(YQ)

GOLANGCI_LINT = $(LOCALBIN)/golangci-lint
GOLANGCI_LINT_VERSION ?= v1.63.4
.PHONY: golangci-lint ## Download golangci-lint locally if necessary.
golangci-lint:
	@[ -f $(GOLANGCI_LINT) ] || { \
	set -e ;\
	curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $(shell dirname $(GOLANGCI_LINT)) $(GOLANGCI_LINT_VERSION) ;\
	}

GEN_CRD_API_REFERENCE_DOCS = $(LOCALBIN)/gen-crd-api-reference-docs
.PHONY: gen-crd-api-reference-docs ## Download gen-crd-api-reference-docs locally if necessary
gen-crd-api-reference-docs: $(GEN_CRD_API_REFERENCE_DOCS)
$(GEN_CRD_API_REFERENCE_DOCS): | $(LOCALBIN)
	@ GOBIN=$(LOCALBIN) go install github.com/ahmetb/gen-crd-api-reference-docs@latest

HELM_DOCS = $(LOCALBIN)/helm-docs
HELM_DOCS_VERSION ?= v1.14.2
.PHONY: helm-docs ## Download helm-docs locally if necessary
helm-docs: $(HELM_DOCS)
$(HELM_DOCS): | $(LOCALBIN)
	@ GOBIN=$(LOCALBIN) go install github.com/norwoodj/helm-docs/cmd/helm-docs@$(HELM_DOCS_VERSION)
##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk command is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

.PHONY: all
all: build

.PHONY: clean
clean: ## clean files
	rm -rf $(LOCALBIN)
	rm -rf $(BUILDDIR)

##@ Development

.PHONY: manifests
manifests: controller-gen ## Generate WebhookConfiguration, ClusterRole and CustomResourceDefinition objects.
	$(CONTROLLER_GEN) crd paths="./api/..." output:crd:artifacts:config=config/crd/bases
	$(CONTROLLER_GEN) rbac:roleName=manager-role webhook paths="./internal/controller/..."
	cp -f config/crd/bases/* deployment/maintenance-operator-chart/crds

.PHONY: generate
generate: controller-gen ## Generate code containing DeepCopy, DeepCopyInto, and DeepCopyObject method implementations.
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./api/..."

.PHONY: test
test: lint unit-test

.PHONY: unit-test
unit-test: envtest ## Run unit tests.
	KUBEBUILDER_ASSETS="$(shell $(ENVTEST) use $(ENVTEST_K8S_VERSION) --bin-dir $(LOCALBIN) -p path)" go test -cover -covermode=$(COVER_MODE) -coverprofile=$(COVER_PROFILE) $(PKGS)

.PHONY: test-e2e
test-e2e: # Run the e2e tests against a k8s instance with maintenance-operator installed.
	go test ./test/e2e/ -v -ginkgo.v -e2e.maintenanceOperatorNamespace=maintenance-operator

.PHONY: lint
lint: golangci-lint ## Run golangci-lint linter & yamllint
	$(GOLANGCI_LINT) run

.PHONY: lint-fix
lint-fix: golangci-lint ## Run golangci-lint linter and perform fixes
	$(GOLANGCI_LINT) run --fixs

.PHONY: generate-mocks
generate-mocks: mockery ## generate mock objects
	PATH=$(LOCALBIN):$(PATH) go generate ./...


.PHONY: generate-api-docs
generate-api-docs: gen-crd-api-reference-docs ## generate api documentation
	$(GEN_CRD_API_REFERENCE_DOCS) -api-dir=./api/v1alpha1 -config=${CURDIR}/hack/api-docs/config.json \
	-template-dir=${CURDIR}/hack/api-docs/templates -out-file=$(BUILDDIR)/api-reference.html
	$(CONTAINER_TOOL) run --rm --volume "`pwd`:/data:Z" pandoc/minimal -f html -t markdown_strict \
	--columns 200 /data/build/api-reference.html -o /data/docs/api-reference.md
	hack/api-docs/fix_links.sh docs/api-reference.md
	chmod a+w docs/api-reference.md

.PHONY: generate-helm-docs
generate-helm-docs: helm-docs ## generate helm documentation
	cd deployment/maintenance-operator-chart && $(HELM_DOCS)

##@ Build

.PHONY: build
build: $(BUILDDIR) ## Build manager binary.
	$(GO_BUILD_OPTS) go build -ldflags $(GO_LDFLAGS) -gcflags="$(GO_GCFLAGS)" -o $(BUILDDIR)/manager cmd/maintenance-manager/main.go

.PHONY: run
run: manifests generate fmt vet ## Run a controller from your host.
	go run ./cmd/maintenance-manager/main.go

# If you wish to build the manager image targeting other platforms you can use the --platform flag.
# (i.e. docker build --platform linux/arm64). However, you must enable docker buildKit for it.
# More info: https://docs.docker.com/develop/develop-images/build_enhancements/
.PHONY: docker-build
docker-build: ## Build docker image with the manager.
	$(CONTAINER_TOOL) build -t ${IMG} .

.PHONY: docker-push
docker-push: ## Push docker image with the manager.
	$(CONTAINER_TOOL) push ${IMG}

# PLATFORMS defines the target platforms for the manager image be built to provide support to multiple
# architectures. (i.e. make docker-buildx IMG=myregistry/mypoperator:0.0.1). To use this option you need to:
# - be able to use docker buildx. More info: https://docs.docker.com/build/buildx/
# - have enabled BuildKit. More info: https://docs.docker.com/develop/develop-images/build_enhancements/
# - be able to push the image to your registry (i.e. if you do not set a valid value via IMG=<myregistry/image:<tag>> then the export will fail)
# To adequately provide solutions that are compatible with multiple platforms, you should consider using this option.
PLATFORMS ?= linux/arm64,linux/amd64,linux/s390x,linux/ppc64le
.PHONY: docker-buildx
docker-buildx: ## Build and push docker image for the manager for cross-platform support
	# copy existing Dockerfile and insert --platform=${BUILDPLATFORM} into Dockerfile.cross, and preserve the original Dockerfile
	sed -e '1 s/\(^FROM\)/FROM --platform=\$$\{BUILDPLATFORM\}/; t' -e ' 1,// s//FROM --platform=\$$\{BUILDPLATFORM\}/' Dockerfile > Dockerfile.cross
	- $(CONTAINER_TOOL) buildx create --name project-v3-builder
	$(CONTAINER_TOOL) buildx use project-v3-builder
	- $(CONTAINER_TOOL) buildx build --push --platform=$(PLATFORMS) --tag ${IMG} -f Dockerfile.cross .
	- $(CONTAINER_TOOL) buildx rm project-v3-builder
	rm Dockerfile.cross

##@ Deployment

ifndef ignore-not-found
  ignore-not-found = false
endif

.PHONY: install
install: manifests kustomize kubectl ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | $(KUBECTL) apply -f -

.PHONY: uninstall
uninstall: manifests kustomize kubectl ## Uninstall CRDs from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/crd | $(KUBECTL) delete --ignore-not-found=$(ignore-not-found) -f -

.PHONY: deploy
deploy: manifests kustomize kubectl ## Deploy controller to the K8s cluster specified in ~/.kube/config.
	cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	$(KUSTOMIZE) build config/default | $(KUBECTL) apply -f -

.PHONY: undeploy
undeploy: kubectl ## Undeploy controller from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/default | $(KUBECTL) delete --ignore-not-found=$(ignore-not-found) -f -

.PHONY: deploy-operator-e2e
deploy-operator-e2e: helm kubectl kind ## Deploy operator to test cluster
	@{ \
		echo "Building test image"; \
		TAG=test make docker-build; \
		echo "Upload test image to kind cluster"; \
		$(KIND) load docker-image $(IMAGE_TAG_BASE):test --name $(TEST_CLUSTER_NAME); \
		echo "deploy operator to kind cluster"; \
		IMAGE_NAME=$$(echo $(IMAGE_TAG_BASE) | awk -F'/' '{print $$NF}'); \
		IMAGE_REPO=$$(echo $(IMAGE_TAG_BASE) | awk -F'/' 'NF>1{NF--; print $0}' OFS='/'); \
		$(HELM) upgrade -i --create-namespace -n maintenance-operator \
			--set operator.image.repository=$$IMAGE_REPO --set operator.image.name=$$IMAGE_NAME --set operator.image.tag=test --set operator.image.imagePullPolicy=Never \
			--set operatorConfig.deploy=true \
			maintenance-operator $(CURDIR)/deployment/maintenance-operator-chart; \
	}

.PHONY: undeploy-operator-e2e
undeploy-operator-e2e: helm ## Undeploy operator from test cluster
	@{ \
		$(HELM) uninstall -n maintenance-operator maintenance-operator; \
		$(KUBECTL) delete ns maintenance-operator; \
	}

##@ Build Dependencies

.PHONY: bundle
bundle: manifests kustomize operator-sdk $(YQ) ## Generate bundle manifests and metadata, then validate generated files.
	$(OPERATOR_SDK) generate kustomize manifests -q
	cd config/manager && $(KUSTOMIZE) edit set image controller=$(IMG)
	$(KUSTOMIZE) build config/manifests | $(OPERATOR_SDK) generate bundle $(BUNDLE_GEN_FLAGS)
	BUNDLE_OCP_VERSIONS=$(BUNDLE_OCP_VERSIONS) TAG=$(IMG) hack/scripts/ocp-bundle-postprocess.sh
	$(OPERATOR_SDK) bundle validate ./bundle

.PHONY: bundle-build
bundle-build: ## Build the bundle image.
	docker build -f bundle.Dockerfile -t $(BUNDLE_IMG) .

.PHONY: bundle-push
bundle-push: ## Push the bundle image.
	$(MAKE) docker-push IMG=$(BUNDLE_IMG)

# A comma-separated list of bundle images (e.g. make catalog-build BUNDLE_IMGS=example.com/operator-bundle:v0.1.0,example.com/operator-bundle:v0.2.0).
# These images MUST exist in a registry and be pull-able.
BUNDLE_IMGS ?= $(BUNDLE_IMG)

# The image tag given to the resulting catalog image (e.g. make catalog-build CATALOG_IMG=example.com/operator-catalog:v0.2.0).
CATALOG_IMG ?= $(IMAGE_TAG_BASE)-catalog:v$(VERSION)

# Set CATALOG_BASE_IMG to an existing catalog image tag to add $BUNDLE_IMGS to that image.
ifneq ($(origin CATALOG_BASE_IMG), undefined)
FROM_INDEX_OPT := --from-index $(CATALOG_BASE_IMG)
endif

# Build a catalog image by adding bundle images to an empty catalog using the operator package manager tool, 'opm'.
# This recipe invokes 'opm' in 'semver' bundle add mode. For more information on add modes, see:
# https://github.com/operator-framework/community-operators/blob/7f1438c/docs/packaging-operator.md#updating-your-existing-operator
.PHONY: catalog-build
catalog-build: opm ## Build a catalog image.
	$(OPM) index add --container-tool docker --mode semver --tag $(CATALOG_IMG) --bundles $(BUNDLE_IMGS) $(FROM_INDEX_OPT)

# Push the catalog image.
.PHONY: catalog-push
catalog-push: ## Push a catalog image.
	$(MAKE) docker-push IMG=$(CATALOG_IMG)

.PHONY: chart-prepare-release
chart-prepare-release: | $(YQ) ## prepare helm chart for release
	@GITHUB_TAG=$(GITHUB_TAG) GITHUB_REPO_OWNER=$(GITHUB_REPO_OWNER) hack/release/chart-update.sh


.PHONY: chart-push-release
chart-push-release: | $(HELM) ## push release helm chart
	@GITHUB_TAG=$(GITHUB_TAG) GITHUB_TOKEN=$(GITHUB_TOKEN) GITHUB_REPO_OWNER=$(GITHUB_REPO_OWNER) hack/release/chart-push.sh

##@ Dev

TEST_CLUSTER_NAME = mn-op

.PHONY: test-env-e2e
test-env-e2e: | $(KIND) $(HELM) $(KUBECTL) ## Create kind cluster for development and e2e tests
	CLUSTER_NAME=$(TEST_CLUSTER_NAME) KIND_BIN=$(KIND) KUBECTL_BIN=$(KUBECTL) $(CURDIR)/hack/scripts/setup_kind.sh
	CLUSTER_NAME=$(TEST_CLUSTER_NAME) HELM_BIN=$(HELM) $(CURDIR)/hack/scripts/install_deps.sh

.PHONY: clean-test-env-e2e
clean-test-env-e2e: | $(KIND) ## Teardown kind cluster for e2e tests
	$(KIND) delete cluster --name $(TEST_CLUSTER_NAME)

.PHONY: dev-operator
dev-operator: | $(KIND) $(SKAFFOLD) ## Deploy maintenance operator controller to test cluster using skaffold
	{\
		$(SKAFFOLD) dev -p operator --cleanup=true --trigger=manual; \
	}

.PHONY: dev-operator-debug
dev-operator-debug: | $(KIND) $(SKAFFOLD) ## Deploy maintenance operator controller to dev cluster using skaffold with remote debug
	{\
		$(SKAFFOLD) debug -p operator --cleanup=true; \
	}
