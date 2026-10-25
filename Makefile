CADDY_BIN ?= ./build/reverse-bin-caddy
RUNTIME_CACHE_DIR ?= $(or $(XDG_CACHE_HOME),$(HOME)/.cache)/reverse-bin-hosting/runtimes
export RUNTIME_CACHE_DIR
PINACT ?= go run github.com/suzuki-shunsuke/pinact/v5/cmd/pinact@latest
NOTES_MAX_WORDS ?= 100
include packaging/runtime-versions.env

# Fixers rewrite the same files; never run targets in parallel.
.NOTPARALLEL:

.PHONY: build deb tests deps-check deps-latest vulncheck release-notes apt-repo sync-sops-recipients clean distclean clean-runtime-cache fetch-runtimes fetch-test-runtimes check-runtime-versions update-runtime-versions smoke-logs-app

build:
	mkdir -p build
	xcaddy build --output $(CADDY_BIN) --with $(CADDY_REVERSE_BIN_PLUGIN)
	$(CADDY_BIN) list-modules | grep http.handlers.reverse-bin
	$(CADDY_BIN) version

deb: fetch-runtimes
	dpkg-buildpackage -us -uc -b

# deps-latest rewrites files; deps-check fails when it did. Run it locally
# and commit the result. vulncheck needs the built package, so CI runs it
# after make deb.
deps-latest: update-runtime-versions
	go get toolchain@latest && go mod tidy
	$(PINACT) run -u

deps-check: deps-latest
	@if [ -n "$$(git status --porcelain)" ]; then git status --short; git diff; \
	echo "error: fixers changed files; commit them" >&2; exit 1; fi

# Run after make deb. Scans the Go binaries we build.
vulncheck:
	./scripts/vulncheck-binaries.sh reverse-bin-caddy

# Usage: make release-notes TAG=vX.Y.Z
release-notes:
	@test -n "$(TAG)" || { echo "usage: make release-notes TAG=vX.Y.Z" >&2; exit 1; }
	@f=release-notes/$(TAG).md; [ -s "$$f" ] || { echo "error: $$f missing" >&2; exit 1; }; \
	n=$$(wc -w < "$$f"); [ "$$n" -le $(NOTES_MAX_WORDS) ] || { \
	echo "error: $$f: $$n words > $(NOTES_MAX_WORDS). Rewrite caveman: fragments, no filler. Keep what changed, breaking, GO/CVE IDs." >&2; exit 1; }

# Builds site/, the GitHub Pages apt repository, from the packages in dist/.
apt-repo:
	rm -rf site
	./scripts/build-apt-repo.sh site dist/*.deb

sync-sops-recipients:
	./scripts/sync-sops-recipients.sh

fetch-runtimes:
	./scripts/fetch-runtimes.sh

fetch-test-runtimes:
	./scripts/fetch-test-runtimes.sh

smoke-logs-app: fetch-runtimes fetch-test-runtimes
	./scripts/smoke-logs-app.sh

check-runtime-versions:
	./scripts/check-runtime-versions.sh

update-runtime-versions:
	./scripts/update-runtime-versions.sh

tests:
	packages=$$(go list ./... 2>/dev/null); \
	if [ -n "$$packages" ]; then \
		go test $$packages; \
	else \
		echo "no Go packages to test"; \
	fi
	./scripts/check-caddy-listeners.sh

clean:
	rm -rf build site debian/.debhelper debian/reverse-bin debian/debhelper-build-stamp debian/files
	rm -f debian/*.debhelper debian/*.debhelper.log debian/*.substvars

distclean: clean

clean-runtime-cache:
	rm -rf $(RUNTIME_CACHE_DIR)
