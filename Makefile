# Tooling for the charts in this repository, modelled on
# DependencyTrack/helm-charts. Every tool runs from a pinned container image
# so the result does not depend on what happens to be installed; only `helm`
# itself (3.13+) and `ct` (for `lint`) are expected on the PATH.
CHART_DIR := charts/stackradar
HELM_DOCS_IMAGE := jnorwood/helm-docs:v1.14.2
HELM_UNITTEST_IMAGE := helmunittest/helm-unittest:4.2.0-1.1.1
KUBECONFORM_IMAGE := ghcr.io/yannh/kubeconform:v0.8.0

# The chart depends on the published stackradar-scanner chart
# (Chart.yaml `dependencies`); `helm dependency build` restores the tarball
# under $(CHART_DIR)/charts/ from Chart.lock. Every other target needs it.
deps:
	helm dependency build $(CHART_DIR)
.PHONY: deps

# Before the scanner version the chart pins is published, package the local
# scanner checkout at that version instead. Development only: the lock file
# is left alone, and a chart packaged this way must never be released.
SCANNER_DIR ?= ../stackradar-scanner/helm
deps-local:
	@v="$$(helm show chart $(CHART_DIR) | awk '/^dependencies:/{d=1} d && /name: stackradar-scanner/{f=1} f && /version:/{print $$2; exit}')"; \
	mkdir -p $(CHART_DIR)/charts && rm -f $(CHART_DIR)/charts/stackradar-scanner-*.tgz && \
	helm package $(SCANNER_DIR) --version "$$v" --app-version "$$v" -d $(CHART_DIR)/charts >/dev/null && \
	echo "packaged $(SCANNER_DIR) as stackradar-scanner-$$v.tgz (local, unreleased)"
.PHONY: deps-local

unit-test:
	docker run --rm -v "$(shell pwd)/$(CHART_DIR):/apps" $(HELM_UNITTEST_IMAGE) .
.PHONY: unit-test

lint:
	ct lint --config ct.yaml
.PHONY: lint

docs:
	docker run --rm -v "$(shell pwd):/helm-docs" -u "$(shell id -u)" $(HELM_DOCS_IMAGE) --chart-search-root $(CHART_DIR)
.PHONY: docs

kubeconform:
	@for f in $(CHART_DIR)/ci/*-values.yaml; do \
		echo "==> kubeconform $$f"; \
		helm template kc $(CHART_DIR) -f $$f \
		  | docker run --rm -i $(KUBECONFORM_IMAGE) -strict -summary -schema-location default \
		      -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
		  || exit 1; \
	done
.PHONY: kubeconform

# Two renders of the same values must be byte-identical: the chart generates
# nothing random (see values.yaml "secrets"), and this is the check that
# keeps it that way.
determinism:
	@a="$$(helm template det $(CHART_DIR) -f $(CHART_DIR)/ci/production-like-values.yaml)"; \
	b="$$(helm template det $(CHART_DIR) -f $(CHART_DIR)/ci/production-like-values.yaml)"; \
	[ "$$a" = "$$b" ] && echo "render is deterministic" || { echo "render differs between two runs"; exit 1; }
.PHONY: determinism
