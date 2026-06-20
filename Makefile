CADDY_BIN ?= ./build/reverse-bin-caddy
CADDY_REVERSE_BIN_PLUGIN := github.com/tarasglek/caddy-reverse-bin@v0.2.1

.PHONY: build deb tests clean

build:
	mkdir -p build
	xcaddy build --output $(CADDY_BIN) --with $(CADDY_REVERSE_BIN_PLUGIN)
	$(CADDY_BIN) list-modules | grep http.handlers.reverse-bin
	$(CADDY_BIN) version

deb:
	dpkg-buildpackage -us -uc -b

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
