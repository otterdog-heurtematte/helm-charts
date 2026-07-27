#
#  *******************************************************************************
#  Copyright (c) 2025 Eclipse Foundation and others.
#  This program and the accompanying materials are made available
#  under the terms of the Eclipse Public License 2.0
#  which is available at http://www.eclipse.org/legal/epl-v20.html
#  SPDX-License-Identifier: EPL-2.0
#  *******************************************************************************
#
HELM_DOCS_VERSION ?= v1.14.2

.PHONY: help docs docs-check

help:  ## Show this help
	@grep -h -E '^[a-zA-Z0-9_%-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-22s\033[0m %s\n", $$1, $$2}'

docs:  ## Regenerate README.md for every chart from its README.md.gotmpl via helm-docs
	@command -v helm-docs >/dev/null || { \
		echo "error: helm-docs not found — install it, e.g.:" >&2; \
		echo "  go install github.com/norwoodj/helm-docs/cmd/helm-docs@$(HELM_DOCS_VERSION)" >&2; \
		exit 1; \
	}
	@for chart in charts/*/; do \
		[ -f "$${chart}README.md.gotmpl" ] || continue; \
		echo "==> Generating $${chart}README.md"; \
		helm-docs --chart-to-generate "$${chart%/}" --sort-values-order=file; \
	done

docs-check: docs  ## Regenerate docs and fail if that changed anything (same check as CI)
	@if ! git diff --exit-code -- $$(for chart in charts/*/; do [ -f "$${chart}README.md.gotmpl" ] && printf '%sREADME.md ' "$$chart"; done); then \
		echo "error: chart docs are out of date — commit the changes made by 'make docs'" >&2; \
		exit 1; \
	fi
