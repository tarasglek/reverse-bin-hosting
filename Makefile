CADDY_BIN ?= ./build/reverse-bin-caddy
RUNTIME_CACHE_DIR ?= $(or $(XDG_CACHE_HOME),$(HOME)/.cache)/reverse-bin-hosting/runtimes
export RUNTIME_CACHE_DIR
include packaging/runtime-versions.env

.PHONY: build deb tests clean distclean clean-runtime-cache fetch-runtimes check-runtime-versions update-runtime-versions

build:
	mkdir -p build
	xcaddy build --output $(CADDY_BIN) --with $(CADDY_REVERSE_BIN_PLUGIN)
	$(CADDY_BIN) list-modules | grep http.handlers.reverse-bin
	$(CADDY_BIN) version

deb: fetch-runtimes
	dpkg-buildpackage -us -uc -b

fetch-runtimes:
	./scripts/fetch-runtimes.sh

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
	python3 -m unittest discover -s utils/discover-app -p 'test_*.py'

clean:
	rm -rf build debian/.debhelper debian/reverse-bin debian/debhelper-build-stamp debian/files
	rm -f debian/*.debhelper debian/*.debhelper.log debian/*.substvars

distclean: clean

clean-runtime-cache:
	rm -rf $(RUNTIME_CACHE_DIR)
