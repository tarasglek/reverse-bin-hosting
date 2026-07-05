# reverse-bin-hosting

Multi-runtime equivalent of https://smallweb.run/ implemented via https://github.com/tarasglek/caddy-reverse-bin/ and packaged into a Debian dpkg package.

This is a work-in-progress.

Reverse-bin’s security goal is to protect the host from apps and apps from each other while keeping sandbox overhead to single-digit milliseconds at app startup. See [`SECURITY-POSTURE.md`](SECURITY-POSTURE.md) for the current isolation model and verification checklist.

## App lifecycle model

- Apps live under `/var/lib/reverse-bin/apps/<app-name>`.
- On incoming request, reverse-bin starts the app and reverse-proxies to it
    1. Prior to launch `reverse-bin-detector` tries either load app config from env var params or discover it as a deno, python, or just static html
        * tries to run them in dev mode eg deno `--watch`
        * envs are loaded from `.env` or SOPS-encrypted `secrets.enc.json`; see [`SECURITY-POSTURE.md`](SECURITY-POSTURE.md) for key isolation details
    2. reverse-bin-detector returns a landrun-secure launch string to caddy 
    3. reverse-bin launches the process 
- The app runs as a subprocess behind a local TCP port or Unix socket. Finding available http ports is race-prone, so few things have unix socket support. Deno pull req https://github.com/denoland/deno/pull/32094
- Caddy/reverse-bin proxies public HTTP traffic to that local app subprocess.
- Reverse-bin injects runtime environment such as `REVERSE_BIN_HOST`, `REVERSE_BIN_PORT`, and `HOME`.
- `HOME` is set to `/var/lib/reverse-bin/apps/<app-name>/data` when the app does not define `HOME` itself.
- App runtime state should live under `/var/lib/reverse-bin/apps/<app-name>/data`.
- Apps run inside a `landrun` sandbox with read access to app source, read-write access to app `data/`, required runtime/system paths, and any network/bind permissions granted by the discovered launch policy.
- App subprocesses are reused while active and terminated after the idle timeout.
- If the discovered runtime uses watch mode, edits in the app directory can restart the subprocess automatically.

Important implications:

- Direct edits under `/var/lib/reverse-bin/apps/` can affect production immediately.
- Files under app `data/` are runtime state, not source.
- $HOME=.../data means package managers and language runtimes should put caches, managed toolchains, virtualenvs, databases, and generated files under app `data/`.
- Eg for deno apps with npm/remote imports, $HOME causes cache state under app `data/` like:
  ```sh
  DENO_DIR=data/.cache/deno
  ```
- TCP apps should also expose `GET /` or configure `REVERSE_BIN_HEALTH_PATH=/health`.
- The Debian package includes runtimes like `uv` at `/usr/lib/reverse-bin/uv`, and `reverse-bin.service` puts `/usr/lib/reverse-bin` on `PATH`.
- Long-lived app subprocesses can hold file locks or database handles until idle termination.

## Runtimes

`packaging/runtime-versions.env` is the source of truth for stable bundled runtime versions: `caddy-reverse-bin`, `uv`, `landrun`, `deno`, `sops`, and `age`. `make update-runtime-versions` refreshes the lockfile to latest upstream stable releases. `make fetch-runtimes` downloads/builds those pinned binaries into `${XDG_CACHE_HOME:-$HOME/.cache}/reverse-bin-hosting/runtimes/` and copies them into `build/` for Debian packaging; CI caches that runtime cache keyed by the lockfile.

## Debian package layout

The package installs these primary paths:

- binary: `/usr/bin/reverse-bin-caddy`
- config entrypoint: selected by `REVERSE_BIN_CADDYFILE` in `/etc/default/reverse-bin`
- packaged configs: `/etc/reverse-bin/Caddyfile.acme`, `/etc/reverse-bin/Caddyfile.http-only`
- defaults: `/etc/default/reverse-bin`
- helper scripts and bundled runtimes: `/usr/lib/reverse-bin/`
- writable app root: `/var/lib/reverse-bin/apps/`
- service home: `/var/lib/reverse-bin/home`
- SOPS age identity: `/var/lib/reverse-bin/keys/age.key`
- SOPS age recipient: `/var/lib/reverse-bin/keys/age.pub`
- security posture checklist: [`SECURITY-POSTURE.md`](SECURITY-POSTURE.md)
- packaged examples: `/usr/share/doc/reverse-bin/examples/`

## Build the Debian package

```bash
make deb
```

This produces a `.deb` in the parent directory.

## Runtime model

- Caddy runs from the packaged systemd unit.
- The service loads deployment-specific variables from `/etc/default/reverse-bin`.
- The service reads the Caddy config path from `REVERSE_BIN_CADDYFILE`.
- App directories live under `/var/lib/reverse-bin/apps/`.
- Example apps ship under `/usr/share/doc/reverse-bin/examples/` and can be copied into the app root.
- The package generates the age identity once on install and never overwrites the private key.

## Instructions

1. Install the package:

```sh
sudo dpkg -i reverse-bin_*_amd64.deb
```

2. Configure one mode in `/etc/default/reverse-bin`.

Direct public HTTPS with Caddy-managed on-demand ACME:

```sh
REVERSE_BIN_CADDYFILE=/etc/reverse-bin/Caddyfile.acme
OPS_EMAIL=admin@example.com
DOMAIN_SUFFIX=example.com
```

Cloudflared or another trusted TLS-terminating proxy:

```sh
REVERSE_BIN_CADDYFILE=/etc/reverse-bin/Caddyfile.http-only
REVERSE_BIN_HTTP_PORT=7777
```

Point Cloudflared ingress at `http://127.0.0.1:${REVERSE_BIN_HTTP_PORT}`. HTTP-only mode binds localhost and is not exposed externally.

3. Restart reverse-bin:

```sh
sudo systemctl restart reverse-bin.service
```

## Logging dashboard

The Debian package seeds a default `logs` app at `/var/lib/reverse-bin/apps/logs/`. Packaged outer Caddy configs write JSON access logs to `/var/lib/reverse-bin/apps/logs/caddy-logs/access.log` so GoAccess can render traffic stats.

The app stays inactive until credentials are generated. After install, run:

```sh
cd /var/lib/reverse-bin/apps/logs
./setup.sh
```

Login user is `admin`; setup stores password in `/var/lib/reverse-bin/apps/logs/.logs-dashboard-password`. See `/var/lib/reverse-bin/apps/logs/README.md` for details.

## Health checks

A passing health check is required before reverse-bin starts proxying. Packaged Caddyfiles define fallback probes, and apps can override them through `.env` or `secrets.enc.json`:

```sh
REVERSE_BIN_HEALTH_METHOD=GET
REVERSE_BIN_HEALTH_PATH=/health
```

For auth-required apps, include an exact expected status:

```sh
REVERSE_BIN_HEALTH_METHOD=GET
REVERSE_BIN_HEALTH_PATH=/v2/
REVERSE_BIN_HEALTH_STATUS=401
```

Set both method and path together. Without `REVERSE_BIN_HEALTH_STATUS`, any `2xx` or `3xx` response is healthy.

## Explicit launch-script apps

Apps can use an explicit launch command through `.env` in the app directory:

```sh
REVERSE_BIN_COMMAND=./launch.sh
REVERSE_BIN_HOST=127.0.0.1
REVERSE_BIN_PORT=
REVERSE_BIN_HEALTH_METHOD=GET
REVERSE_BIN_HEALTH_PATH=/v2/
REVERSE_BIN_HEALTH_STATUS=401
```

- `REVERSE_BIN_COMMAND` is the command `reverse-bin-detector` runs.
- Blank `REVERSE_BIN_PORT=` asks the detector to allocate a free TCP port and inject the resolved value into the child environment.
- Missing `REVERSE_BIN_HOST` defaults to `127.0.0.1`.
- App launch scripts should bind to `REVERSE_BIN_HOST` and `REVERSE_BIN_PORT`.
- App launch scripts may use packaged `uv` directly; it is available on the reverse-bin service `PATH`.
- `HOME` defaults to app `data/`, so tools that respect `HOME` can keep runtime state there. If a tool uses separate cache/data variables, set them explicitly in `.env` or `launch.sh`.
- `REVERSE_BIN_HEALTH_STATUS` is optional and enables exact-status health checks like registry `/v2/` returning `401`.

Wrangler apps use this same explicit launch-script pattern; there is no Wrangler-specific detector or separate sandbox wrapper in the compatibility path.

## Encrypted app env files

Apps may use either plaintext `.env` or encrypted `secrets.enc.json`, not both. `reverse-bin-detector` rejects app directories containing both files to avoid ambiguous secret sources.

Create plaintext dotenv first:

```sh
REVERSE_BIN_COMMAND=./launch.sh
REVERSE_BIN_HOST=127.0.0.1
REVERSE_BIN_PORT=
SECRET_KEY=change-me
```

The package seeds `/var/lib/reverse-bin/apps/.sops.yaml` with the reverse-bin server key. For app checkouts elsewhere, create `.sops.yaml` with the package age recipient plus your SSH public key. The age recipient lets reverse-bin decrypt at runtime; the SSH public key lets you edit secrets without access to the server private key.

```bash
SERVER_RECIPIENT=$(cat /var/lib/reverse-bin/keys/age.pub)
SSH_RECIPIENT="$(awk '{print $1" "$2}' ~/.ssh/id_ed25519.pub)"
cat > .sops.yaml <<EOF
creation_rules:
  - path_regex: secrets\\.enc\\.json$
    key_groups:
      - age:
        - $SERVER_RECIPIENT # reverse-bin server key: /var/lib/reverse-bin/keys/age.pub
        - $SSH_RECIPIENT # your SSH public key for editing secrets
EOF
```

For GitHub-managed SSH keys, `github-to-sops` can add users to an existing `.sops.yaml`. Example: add your current GitHub account using `gh` and `uv`:

```bash
GITHUB_USER=$(gh api user --jq .login)
uvx github-to-sops --github-users "$GITHUB_USER" import-keys --inplace-edit .sops.yaml
```

Later, refresh GitHub keys and re-encrypt committed secrets with:

```bash
uvx github-to-sops updatekeys
```

See: https://github.com/tarasglek/github-to-sops

Encrypt `.env` to JSON, then remove plaintext only after encryption succeeds:

```bash
sops --encrypt --input-type dotenv --output-type json --filename-override secrets.enc.json .env > secrets.enc.json && rm .env
```

At runtime, systemd sets `SOPS_AGE_KEY_FILE=/var/lib/reverse-bin/keys/age.key`. `reverse-bin-detector` decrypts `secrets.enc.json` in memory with bundled `/usr/lib/reverse-bin/sops`, asks SOPS to output dotenv, and passes parsed keys to the child app. The private key stays outside app directories; child apps only receive `SOPS_AGE_KEY_FILE` if the app env explicitly defines it.

## Credits and inspiration

- Smallweb for simple app-directory hosting and the Deno runtime shape.
- Nixpacks for provider-style source detection patterns.
- Cloud Native Buildpacks and Heroku buildpacks for detect-phase concepts.
- pledge, unveil, Landlock, and Deno permissions for sandbox policy vocabulary.

## related projects

* https://github.com/sablierapp/sablier
* https://github.com/losfair/zeroserve
