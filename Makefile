##@ General

# VERSION defines the project version.
# Update this value when you upgrade the version of your project.
# To re-generate a bundle for another specific version without changing the standard setup, you can:
# - use the VERSION as arg of the build target (e.g make build VERSION=0.0.2)
# - use environment variables to overwrite this value (e.g export VERSION=0.0.2)
VERSION ?= 0.4.0

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

# Get the OS to set platform specific commands
UNAME_S ?= $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
	CP_FLAGS = -v -n
else
	CP_FLAGS = -v --update=none
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

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
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

##@ Build

.PHONY: all
all: build ## Build slurm-operator.

REGISTRY ?= slinky.slurm.net
BUILDER ?= project-v3-builder

.PHONY: build
build: build-images build-chart ## Build OCI packages.

.PHONY: build-images
build-images: ## Build container images.
	- $(CONTAINER_TOOL) buildx create --name $(BUILDER)
	REGISTRY=$(REGISTRY) VERSION=$(VERSION) $(CONTAINER_TOOL) buildx bake --builder=$(BUILDER)

.PHONY: build-chart
build-chart: ## Build charts.
	$(foreach chart, $(wildcard ./helm/**/Chart.yaml), helm package --dependency-update helm/$(shell basename "$(shell dirname "${chart}")") ;)

.PHONY: push
push: push-images push-charts ## Push OCI packages.

.PHONY: push-images
push-images: build-images ## Push container images.
	REGISTRY=$(REGISTRY) VERSION=$(VERSION) $(CONTAINER_TOOL) buildx bake --builder=$(BUILDER) --push

.PHONY: push-charts
push-charts: build-chart ## Push OCI packages.
	$(foreach chart, $(wildcard ./*.tgz), helm push ${chart} oci://$(REGISTRY)/charts ;)

.PHONY: clean
clean: ## Clean executable files.
	@ chmod -R -f u+w bin/ || true # make test installs files without write permissions.
	rm -rf bin/
	rm -rf vendor/
	rm -f cover.out cover.html
	rm -f *.tgz
	- $(CONTAINER_TOOL) buildx rm $(BUILDER)

.PHONY: run
run: manifests generate fmt tidy vet ## Run a controller from your host.
	go run ./cmd/manager/main.go

##@ Deployment

ifndef ignore-not-found
  ignore-not-found = false
endif

.PHONY: install
install: manifests kustomize ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | $(KUBECTL) apply --server-side=true --force-conflicts -f -

.PHONY: uninstall
uninstall: manifests kustomize ## Uninstall CRDs from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/crd | $(KUBECTL) delete --ignore-not-found=$(ignore-not-found) -f -

##@ Build Dependencies

## Location to install dependencies to
LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

# go-install-tool will 'go install' any package with custom target and name of binary, if it doesn't exist
# $1 - target path with name of binary (ideally with version)
# $2 - package url which can be installed
# $3 - specific version of package
define go-install-tool
@[ -f $(1) ] || { \
set -e; \
package=$(2)@$(3) ;\
echo "Downloading $${package}" ;\
GOBIN=$(LOCALBIN) go install $${package} ;\
mv "$$(echo "$(1)" | sed "s/-$(3)$$//")" $(1) ;\
}
endef

## Tool Binaries
KUBECTL ?= kubectl
KUSTOMIZE ?= $(LOCALBIN)/kustomize-$(KUSTOMIZE_VERSION)
CONTROLLER_GEN ?= $(LOCALBIN)/controller-gen-$(CONTROLLER_TOOLS_VERSION)
OPERATOR_SDK ?= $(LOCALBIN)/operator-sdk-$(OPERATOR_SDK_VERSION)
ENVTEST ?= $(LOCALBIN)/setup-envtest-$(ENVTEST_VERSION)
GOVULNCHECK ?= $(LOCALBIN)/govulncheck-$(GOVULNCHECK_VERSION)
GOLANGCI_LINT ?= $(LOCALBIN)/golangci-lint-$(GOLANGCI_LINT_VERSION)
HELM_DOCS ?= $(LOCALBIN)/helm-docs-$(HELM_DOCS_VERSION)
PANDOC ?= $(LOCALBIN)/pandoc-$(PANDOC_VERSION)

## Tool Versions
KUSTOMIZE_VERSION ?= v5.6.0
CONTROLLER_TOOLS_VERSION ?= v0.18.0
OPERATOR_SDK_VERSION ?= v1.39.2
# ENVTEST_K8S_VERSION refers to the version of kubebuilder assets to be downloaded by envtest binary.
ENVTEST_K8S_VERSION ?= $(shell go list -m -f "{{ .Version }}" k8s.io/api | awk -F'[v.]' '{printf "1.%d", $$3}')
ENVTEST_VERSION ?= $(shell go list -m -f "{{ .Version }}" sigs.k8s.io/controller-runtime | awk -F'[v.]' '{printf "release-%d.%d", $$2, $$3}')
GOVULNCHECK_VERSION ?= latest
GOLANGCI_LINT_VERSION ?= v2.1.6
HELM_DOCS_VERSION ?= v1.14.2
PANDOC_VERSION ?= 3.7.0.2

.PHONY: kustomize
kustomize: $(KUSTOMIZE) ## Download kustomize locally if necessary.
$(KUSTOMIZE): $(LOCALBIN)
	$(call go-install-tool,$(KUSTOMIZE),sigs.k8s.io/kustomize/kustomize/v5,$(KUSTOMIZE_VERSION))

.PHONY: controller-gen
controller-gen: $(CONTROLLER_GEN) ## Download controller-gen locally if necessary.
$(CONTROLLER_GEN): $(LOCALBIN)
	$(call go-install-tool,$(CONTROLLER_GEN),sigs.k8s.io/controller-tools/cmd/controller-gen,$(CONTROLLER_TOOLS_VERSION))

.PHONY: envtest
envtest: $(ENVTEST) ## Download setup-envtest locally if necessary.
$(ENVTEST): $(LOCALBIN)
	$(call go-install-tool,$(ENVTEST),sigs.k8s.io/controller-runtime/tools/setup-envtest,$(ENVTEST_VERSION))

.PHONY: govulncheck-bin
govulncheck-bin: $(GOVULNCHECK) ## Download govulncheck locally if necessary.
$(GOVULNCHECK): $(LOCALBIN)
	$(call go-install-tool,$(GOVULNCHECK),golang.org/x/vuln/cmd/govulncheck,$(GOVULNCHECK_VERSION))

.PHONY: golangci-lint-bin
golangci-lint-bin: $(GOLANGCI_LINT) ## Download golangci-lint locally if necessary.
$(GOLANGCI_LINT): $(LOCALBIN)
	@if ! [ -f "$(GOLANGCI_LINT)" ]; then \
		wget -O- -nv https://raw.githubusercontent.com/golangci/golangci-lint/HEAD/install.sh | sh -s -- -b $(LOCALBIN) $(GOLANGCI_LINT_VERSION) ;\
		mv $(LOCALBIN)/golangci-lint $(GOLANGCI_LINT) ;\
	fi

.PHONY: helm-docs-bin
helm-docs-bin: $(HELM_DOCS) ## Download helm-docs locally if necessary.
$(HELM_DOCS): $(LOCALBIN)
	$(call go-install-tool,$(HELM_DOCS),github.com/norwoodj/helm-docs/cmd/helm-docs,$(HELM_DOCS_VERSION))

.PHONY: pandoc-bin
pandoc-bin: $(PANDOC) ## Download pandoc locally if necessary.
$(PANDOC): $(LOCALBIN)
	@if ! [ -f "$(PANDOC)" ]; then \
		if [ "$(shell go env GOOS)" != "darwin" ]; then \
			curl -sSLo $(PANDOC).tar.gz https://github.com/jgm/pandoc/releases/download/$(PANDOC_VERSION)/pandoc-$(PANDOC_VERSION)-$(shell go env GOOS)-$(shell go env GOARCH).tar.gz ;\
			tar xv --directory=$(LOCALBIN) --file=$(PANDOC).tar.gz pandoc-$(PANDOC_VERSION)/bin/pandoc --strip-components=2 ;\
		else \
			curl -sSLo $(PANDOC).zip https://github.com/jgm/pandoc/releases/download/$(PANDOC_VERSION)/pandoc-$(PANDOC_VERSION)-$(shell go env GOARCH)-macOS.zip ;\
			unzip -oqqjd $(LOCALBIN) $(PANDOC).zip ;\
		fi ;\
		mv $(LOCALBIN)/pandoc $(PANDOC) ;\
		rm -f $(PANDOC).tar.gz $(PANDOC).zip ;\
	fi


.PHONY: operator-sdk
operator-sdk: ## Download operator-sdk locally if necessary.
ifeq (,$(wildcard $(OPERATOR_SDK)))
ifeq (, $(shell which operator-sdk 2>/dev/null))
	@{ \
	set -e ;\
	mkdir -p $(dir $(OPERATOR_SDK)) ;\
	OS=$(shell go env GOOS) && ARCH=$(shell go env GOARCH) && \
	curl -sSLo $(OPERATOR_SDK) https://github.com/operator-framework/operator-sdk/releases/download/$(OPERATOR_SDK_VERSION)/operator-sdk_$${OS}_$${ARCH} ;\
	chmod +x $(OPERATOR_SDK) ;\
	}
else
OPERATOR_SDK = $(shell which operator-sdk)
endif
endif

##@ Development

.PHONY: install-dev
install-dev: ## Install binaries for development environment.
	go install github.com/go-delve/delve/cmd/dlv@latest
	go install sigs.k8s.io/kind@latest
	go install sigs.k8s.io/cloud-provider-kind@latest

.PHONY: helm-validate
helm-validate: helm-dependency-update helm-lint ## Validate Helm charts.

.PHONY: helm-unittest
helm-unittest: ## Run helm-unittest.
	@command -v helm unittest >/dev/null 2>&1 || helm plugin install https://github.com/helm-unittest/helm-unittest
	@echo "Running helm unittest for slurm-operator chart"
	@helm unittest helm/slurm-operator

.PHONY: helm-docs
helm-docs: helm-docs-bin ## Run helm-docs.
	$(HELM_DOCS) --chart-search-root=helm

.PHONY: helm-lint
helm-lint: ## Lint Helm charts.
	find "helm/" -depth -mindepth 1 -maxdepth 1 -type d -print0 | xargs -0r -n1 helm lint --strict

.PHONY: helm-dependency-update
helm-dependency-update: ## Update Helm chart dependencies.
	find "helm/" -depth -mindepth 1 -maxdepth 1 -type d -print0 | xargs -0r -n1 helm dependency update

.PHONY: values-dev
values-dev: ## Safely initialize values-dev.yaml files for Helm charts.
	find "helm/" -type f -name "values.yaml" | sed 'p;s/\.yaml/-dev\.yaml/' | xargs -n2 cp $(CP_FLAGS)

.PHONY: manifests
manifests: controller-gen ## Generate WebhookConfiguration, ClusterRole and CustomResourceDefinition objects.
	rm -f config/crd/bases/*.yaml
	$(CONTROLLER_GEN) rbac:roleName=manager-role crd:generateEmbeddedObjectMeta=true webhook paths="./..." output:crd:artifacts:config=config/crd/bases
	rm -f helm/slurm-operator-crds/templates/*.yaml
	$(CONTROLLER_GEN) rbac:roleName=manager-role crd:generateEmbeddedObjectMeta=true webhook paths="./..." output:crd:artifacts:config=helm/slurm-operator-crds/templates

.PHONY: generate
generate: controller-gen ## Generate code containing DeepCopy, DeepCopyInto, and DeepCopyObject method implementations.
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."
	go generate ./...

.PHONY: generate-docs
generate-docs: pandoc-bin
	$(PANDOC) --quiet README.md -o docs/index.rst
	printf '\n' >> docs/index.rst
	cat ./docs/_static/toc.rst >> docs/index.rst
	sed -i -E '/<.\/docs\/[A-Za-z]*.md/s/.\/docs\///g' docs/index.rst
	sed -i -E '/.\/docs\/.*.svg/s/.\/docs\///g' docs/index.rst
	sed -i -E '/<[A-Za-z]*.md>`/s/.md>/.html>/g' docs/index.rst

DOCS_IMAGE ?= $(REGISTRY)/sphinx

.PHONY: build-docs
build-docs: ## Build the container image used to develop the docs
	$(CONTAINER_TOOL) build -t $(DOCS_IMAGE) ./docs

.PHONY: run-docs
run-docs: build-docs ## Run the container image for docs development
	$(CONTAINER_TOOL) run --rm --network host -v ./docs:/docs:z $(DOCS_IMAGE) sphinx-autobuild --port 8000 /docs /build/html

.PHONY: fmt
fmt: ## Run go fmt against code.
	go fmt ./...

.PHONY: tidy
tidy: ## Run go mod tidy against code
	go mod tidy

.PHONY: get-u
get-u: ## Run `go get -u`
	go get -u ./...
	$(MAKE) tidy

.PHONY: vet
vet: ## Run go vet against code.
	go vet ./...

.PHONY: govulncheck
govulncheck: govulncheck-bin ## Run govulncheck
	$(GOVULNCHECK) ./...

# https://github.com/golangci/golangci-lint/blob/main/.pre-commit-hooks.yaml
.PHONY: golangci-lint
golangci-lint: golangci-lint-bin ## Run golangci-lint.
	$(GOLANGCI_LINT) run --fix

# https://github.com/golangci/golangci-lint/blob/main/.pre-commit-hooks.yaml
.PHONY: golangci-lint-fmt
golangci-lint-fmt: golangci-lint-bin ## Run golangci-lint fmt.
	$(GOLANGCI_LINT) fmt

CODECOV_PERCENT ?= 67

.PHONY: test
test: envtest ## Run tests.
	rm -f cover.out cover.html
	KUBEBUILDER_ASSETS="$(shell $(ENVTEST) use $(ENVTEST_K8S_VERSION) --bin-dir $(LOCALBIN) -p path)" \
	go test `go list ./... | grep -v "/api"` -v -coverprofile cover.out
	go tool cover -func cover.out
	go tool cover -html cover.out -o cover.html
	@percentage=$$(go tool cover -func=cover.out | grep ^total | awk '{print $$3}' | tr -d '%'); \
		if (( $$(echo "$$percentage < $(CODECOV_PERCENT)" | bc -l) )); then \
			echo "----------"; \
			echo "Total test coverage ($${percentage}%) is less than the coverage threshold ($(CODECOV_PERCENT)%)."; \
			exit 1; \
		fi
