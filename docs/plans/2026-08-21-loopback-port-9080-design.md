# Loopback-only port 9080 design

Port 9080 is an internal ACME authorization endpoint. A Caddy site address such as `http://127.0.0.1:9080` restricts the HTTP host matcher but still creates a listener on every interface, so it does not provide network isolation.

Add an explicit `bind 127.0.0.1` to every Caddy server using port 9080 in `caddy-reverse-bin` and `reverse-bin-hosting`. Keep the ACME authorization URL unchanged. Add configuration regression checks that adapt each Caddyfile and assert the effective listener is exactly `127.0.0.1:9080`.

Release a new `reverse-bin-hosting` Debian package, monitor tagged CI, install its artifact on this host, restart the service in ACME mode, and verify the live socket is loopback-only. Preserve existing package configuration and application data during upgrade.
