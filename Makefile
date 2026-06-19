CADDY_BIN ?= ./build/reverse-bin-caddy

.PHONY: build deb tests clean

build:
	mkdir -p build
	go build -o $(CADDY_BIN) ./cmd/caddy
	$(CADDY_BIN) list-modules | grep http.handlers.reverse-bin
	$(CADDY_BIN) version

deb:
	dpkg-buildpackage -us -uc -b

tests:
	go test ./...
	python3 -m unittest discover -s utils/discover-app -p 'test_*.py'

clean:
	rm -rf build debian/.debhelper debian/reverse-bin debian/debhelper-build-stamp debian/files
	rm -f debian/*.debhelper debian/*.debhelper.log debian/*.substvars
