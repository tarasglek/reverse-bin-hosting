# Repository Review

Systems-engineer review of `reverse-bin-hosting`.

Verification run:

- `make tests` passes: Go package + 55 Python tests OK.
- Repository was reviewed statically for architecture, packaging, deployment, security, operations, and correctness.

## High-priority findings

### 3. The sandbox is permissive enough to be misleading

Location: `utils/discover-app/discover-app.py`

The landrun wrapper defaults to unrestricted network access:

```python
unrestricted_network: bool = True
...
wrapper.append("--unrestricted-network")
```

Deno detection also launches with full permissions:

```python
deno serve --watch --allow-all
```

So the documented sandbox does not meaningfully restrict network access, and Deno apps get full permissions.

**Recommendation:** either describe this as process isolation rather than sandboxing, or implement explicit allowlists. Default should be restricted network, with opt-in outbound access.

### 4. `HOME` behavior contradicts README

Location: `utils/discover-app/discover-app.py`

README says `HOME` is set to app `data/` only when the app does not define `HOME` itself. The code overwrites app-defined `HOME` whenever `data/` exists:

```python
if (data_dir := working_dir / "data").is_dir():
    env_map["HOME"] = str(data_dir.resolve())
```

**Recommendation:** preserve explicit app configuration:

```python
if "HOME" not in env_map and (data_dir := working_dir / "data").is_dir():
    env_map["HOME"] = str(data_dir.resolve())
```

Add a regression test.

### 5. Port allocation has a race

Location: `utils/discover-app/discover-app.py`

`find_free_port()` binds to port 0, closes the socket, then later the child process binds to that port. Between those steps another process or concurrent request can claim the port.

**Impact:** flaky launches under concurrency; possible local port hijack.

**Recommendation:** prefer Unix sockets where possible, have reverse-bin reserve/pass a listener FD, or allocate ports with retry on bind failure.

## Medium-priority findings

### 6. Release document is stale and misspelled

Location: `RELESE-PROCESS.md`

The file name is misspelled. The content says:

```md
# Release Process (caddy-reverse-bin)
```

But this repository is `reverse-bin-hosting`.

The validation checklist also expects `/etc/reverse-bin/Caddyfile`, while active configs are selected through `/etc/default/reverse-bin` and include `Caddyfile.acme` / `Caddyfile.http-only`.

**Recommendation:** rename to `RELEASE-PROCESS.md` and update the package validation checklist.

### 7. `postrm purge` destroys all app data

Location: `debian/postrm`

```sh
rm -rf /var/lib/reverse-bin
```

This removes apps, secrets, generated age keys, app state, databases, and other production data.

Debian purge may remove package-owned state, but `/var/lib/reverse-bin/apps` is user production data and should be treated carefully.

**Recommendation:** preserve apps and keys on purge, or document and gate the destructive behavior very explicitly. Prefer not deleting `/var/lib/reverse-bin/apps` automatically.

### 8. Bundled runtime binaries create package and maintenance risk

Locations: `debian/rules`, `debian/install`

The package bundles `deno`, `uv`, `landrun`, `sops`, `age`, and `age-keygen`. This explains previous large-file/GitHub push problems and creates an update/security-maintenance burden: the package maintainer must track CVEs and updates for all bundled runtimes.

**Recommendation:** prefer distro dependencies where possible. If bundling is intentional, add deterministic checksums, version reporting, and SBOM/release documentation.

### 9. systemd hardening is minimal

Location: `debian/reverse-bin.service`

The service correctly runs as the `reverse-bin` user, but lacks common systemd hardening options such as:

- `NoNewPrivileges=true`
- `PrivateTmp=true`
- `ProtectSystem=...`
- `ProtectHome=true`
- `ReadWritePaths=/var/lib/reverse-bin /run/reverse-bin`
- `CapabilityBoundingSet=CAP_NET_BIND_SERVICE`
- `RestrictAddressFamilies=...`

**Recommendation:** add systemd sandboxing around Caddy/reverse-bin itself, while preserving required access to `/var/lib/reverse-bin`, `/run/reverse-bin`, and packaged binaries.

## Lower-priority cleanup

- `packaging/debian/reverse-bin.service` duplicates `debian/reverse-bin.service`; one likely should be removed or generated from the other.
- `debian/control` has placeholder maintainer email `taras@example.com`.
- README is generally good, but the security model should explicitly say apps can run arbitrary code and currently get unrestricted outbound network.
- `REVERSE_BIN_COMMAND` parsing via `sh -c` is flexible, but should be documented as shell execution.

## Overall assessment

This is a good prototype packaging repository. The test suite passes and the app-discovery code is reasonably covered. The biggest remaining engineering risks are:

1. Misleading sandbox/security posture.
2. Dangerous state deletion on purge.
3. Runtime and package maintenance complexity from bundled binaries.

These should be fixed before treating the package as production-ready or public-release quality.
