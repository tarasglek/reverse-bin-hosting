# Security Posture Checklist

Reverse-bin runs untrusted or semi-trusted apps from `/var/lib/reverse-bin/apps`. Default posture: minimal host access, explicit app access, layered Linux isolation.

_Last checked against package state on 2026-07-19: `reverse-bin-detector 0.1.12`, package `0.0.5-1`, and `debian/reverse-bin.service`._

## Goals

- [x] Protect host from app code with Landlock (`landrun`) filesystem/network policy plus process namespaces.
- [x] Protect apps from each other at the filesystem policy and process-list level.
- [x] Protect operator/user homes from packaged reverse-bin Caddy and app subprocesses with `ProtectHome=yes` plus per-app Landlock policy.
- [x] Keep app ergonomics: app directory plus `data/` writable state.
- [x] Prefer kernel-native, minimal, auditable primitives over heavy orchestration.

## Current packaged baseline

The packaged systemd service currently provides service-wide isolation and environment:

- [x] Runs as dedicated `reverse-bin` user/group.
- [x] Sets `WorkingDirectory=/var/lib/reverse-bin/home`.
- [x] Sets `RuntimeDirectory=reverse-bin` for `/run/reverse-bin`.
- [x] Sets `ProtectHome=yes`.
- [x] Sets `SOPS_AGE_KEY_FILE=/var/lib/reverse-bin/keys/age.key` for the detector.
- [x] Puts packaged runtimes on `PATH` with `/usr/lib/reverse-bin:/usr/bin:/bin`.
- [ ] Sets `NoNewPrivileges=yes`.
- [ ] Sets `PrivateTmp=yes`.
- [ ] Sets `ProtectSystem=strict` with explicit writable paths.

`ProtectHome=yes` is service-wide systemd isolation. It applies to reverse-bin Caddy, the detector, and inherited app subprocesses unless an app launcher creates a different mount namespace. In the packaged service this blocks access to `/home`, `/root`, and `/run/user`, protecting operator home directories, SSH keys, shell history, browser profiles, and user config by default. App-specific writable state must use `/var/lib/reverse-bin/apps/<app>/data`, not `/home`.

Recommended next systemd hardening:

- [ ] Add `NoNewPrivileges=yes`.
- [ ] Add `PrivateTmp=yes` after confirming app launchers do not depend on host `/tmp`.
- [ ] Add `ProtectSystem=strict`.
- [ ] Add `ReadWritePaths=/var/lib/reverse-bin /run/reverse-bin`.

## Per-app isolation

Per-app isolation belongs in `reverse-bin-detector` or its launch wrapper, not only in systemd. Systemd isolates the reverse-bin service as a whole; it does not give each app its own PID namespace unless each app becomes a separate systemd unit.

Current detector baseline:

- [x] Uses `landrun` for Landlock filesystem and network policy.
- [x] Gives apps read/execute access to app source.
- [x] Gives apps read/write access to app `data/`.
- [x] Gives apps only required runtime/system paths.
- [x] Uses two runtime policies: static website apps remain network-restricted, while all executable apps receive unrestricted networking for runtime compatibility.
- [x] Gives each launched app its own PID namespace.
- [x] Mounts a private `/proc` matching that PID namespace.
- [x] Prevents apps from seeing the host process list through `/proc`.
- [x] Prevents apps from seeing sibling app processes through `/proc`.
- [x] Adds IPC namespace isolation.
- [x] Adds UTS namespace isolation.
- [x] Uses a shared host `reverse-bin` UID intentionally for app processes.
- [x] Uses `--map-current-user` so app namespaces map to the service UID, not root.
- [x] Treats per-app host UIDs as potential defense-in-depth, not baseline isolation.

Current wrapper shape returned by `reverse-bin-detector 0.1.12`:

```sh
unshare \
  --map-current-user \
  --pid --fork --mount-proc \
  --ipc --uts --kill-child -- \
  landrun ... app command ...
```

Apps intentionally run under the shared host `reverse-bin` UID. `--map-current-user` maps the app namespace to that service UID instead of root, so existing `reverse-bin`-owned `data/` writes continue to work.

Isolation is provided by Landlock path/network rules plus per-app PID/private `/proc`, IPC, and UTS namespaces, not by Unix user separation. Apps cannot enumerate host or sibling processes through `/proc` or access paths outside their Landlock allowlist. Writable paths are limited to app `data/` plus, for static apps, the exact reverse-bin-managed runtime socket directory.

Per-app host UIDs are potential defense-in-depth only. They would not add protection under the current allowlist and namespace policy, so they are not part of the baseline.

## Filesystem policy

Current detector policy for launched apps:

- [x] App source is read/execute-only in the Landlock sandbox (`--rox <app-dir>`).
- [x] Non-static app `data/` is read/write when present (`--rw <app-dir>/data`).
- [x] Static apps receive read/write access only to `/run/reverse-bin/static-apps/app-<hash>/` for their managed socket; app `data/` remains read-only with the rest of the source tree.
- [x] `HOME` defaults to app `data/` when the app does not define `HOME`.
- [x] `TMPDIR` defaults to `data`.
- [x] Reverse-bin keys are outside app policy and inaccessible to apps.
- [x] `/home` is inaccessible by default in the packaged service.
- [x] `/root` is inaccessible by default in the packaged service.
- [x] `/run/user` is inaccessible by default in the packaged service.
- [x] Runtime binaries under `/usr/lib/reverse-bin` are executable/read-only through the `/usr` read/execute policy.
- [x] Config under `/etc` is read-only in the Landlock sandbox.
- [x] `/proc` is private to the app PID namespace.
- [x] `/sys/fs/cgroup` is exposed read/execute for cgroup metadata.
- [x] Executable apps receive read-only `/sys` access required by runtimes such as Chromium; static apps do not.
- [x] `/dev` is read/write as currently required by common runtimes.

Common filesystem policy shape:

```sh
landrun \
  --rox /bin,/usr,/lib,/lib64,/proc,/sys/fs/cgroup \
  --ro /etc \
  --rw /dev \
  --rox <app-dir> \
  ...
```

Executable apps add `--rw <app-dir>/data` when that directory exists, `--ro /sys`, and `--unrestricted-network`. Static apps instead add only `--rw /run/reverse-bin/static-apps/app-<hash>` for their managed socket and receive no network access.

## Secrets

- [x] Package install creates `/var/lib/reverse-bin/keys/age.key` mode `0600`, owned by `reverse-bin:reverse-bin`.
- [x] Package install creates `/var/lib/reverse-bin/keys/age.pub` mode `0644`.
- [x] Systemd sets `SOPS_AGE_KEY_FILE=/var/lib/reverse-bin/keys/age.key` for the service.
- [x] Detector may use the key to decrypt app `secrets.enc.json`.
- [x] Apps may use plaintext `.env` or encrypted `secrets.enc.json`, not both.
- [x] Child apps receive decrypted environment values only.
- [x] Child apps do not receive `SOPS_AGE_KEY_FILE` unless explicitly configured by app env.
- [x] Child apps cannot read `/var/lib/reverse-bin/keys` through the default Landlock policy.
- [x] Package seeds `/var/lib/reverse-bin/apps/.sops.yaml` with the server age recipient.

## Network policy

Apps intentionally share the host network namespace.

Default network policy depends on app type and transport. Static website apps run as nested `reverse-bin-caddy file-server` processes over reverse-bin-managed Unix sockets under `/run/reverse-bin/static-apps/app-<hash>/`. Static apps never use TCP listeners, reject TCP listener environment configuration, require no TCP bind permission, and need no outbound network access for normal serving.

All executable runtimes use `landrun --unrestricted-network` for consistent runtime behavior, including outbound access. This also allows executable apps to bind arbitrary ports in the shared host network namespace. The desired future policy remains narrower: restrict listen/bind to the assigned app port while independently allowing outbound connects.

Landlock also enforces filesystem access: app source is read/execute-only, non-static app `data/` is read/write when present, `/etc` is read-only, required runtime paths are read/execute-only, and reverse-bin keys and sibling app state are outside the allowlist. Static apps instead receive only their exact managed runtime socket directory as writable.

- [x] Packaged HTTP-only Caddy mode binds only `127.0.0.1:${REVERSE_BIN_HTTP_PORT:-7777}`.
- [x] ACME mode uses Caddy-managed HTTPS with on-demand TLS and an ask endpoint restricted to the configured domain suffix.
- [x] Apps share the host network namespace intentionally.
- [x] Static website apps use nested `reverse-bin-caddy file-server` over a Unix socket under `/run/reverse-bin/static-apps/app-<hash>/`.
- [x] Static website apps require no TCP bind permission in their runtime sandbox.
- [x] Static website apps require no outbound network access for normal serving.
- [x] All executable apps use unrestricted networking for runtime compatibility.
- [x] Landlock restricts filesystem access to app source, app `data/`, the static app's exact runtime socket directory when applicable, and required runtime paths.
- [x] Apps may use Unix sockets under app `data/` when runtime/app config supports them.
- [ ] Potential hardening: separate connect and bind policy so executable runtimes can restrict listeners while keeping outbound connects unrestricted.

## Verification commands

Systemd/service checks:

```sh
systemd-analyze security reverse-bin.service
sudo systemctl show reverse-bin.service \
  -p User -p Group -p WorkingDirectory -p RuntimeDirectory \
  -p ProtectHome -p NoNewPrivileges -p PrivateTmp -p ProtectSystem -p ReadWritePaths \
  -p Environment
```

Detector launch-policy smoke check:

```sh
app=$(mktemp -d)
mkdir -p "$app/data"
printf 'hello\n' > "$app/index.html"
/usr/lib/reverse-bin/reverse-bin-detector "$app" | jq .executable
rm -rf "$app"
```

Expected executable prefix:

```text
unshare --map-current-user --pid --fork --mount-proc --ipc --uts --kill-child -- landrun ...
```

App isolation checks:

- [x] App cannot read `/home` in the packaged service. Verified from live `logs` GoAccess app namespace on 2026-07-05.
- [x] App cannot read `/root` in the packaged service. Verified from live `logs` GoAccess app namespace on 2026-07-05.
- [x] App cannot read `/run/user` in the packaged service. Verified from live `logs` GoAccess app namespace on 2026-07-05.
- [x] App cannot read `/var/lib/reverse-bin/keys/age.key`. Verified from live `logs` GoAccess app namespace plus app Landlock policy on 2026-07-05.
- [x] App cannot write outside its `data/` directory, except that static apps can write their exact managed runtime socket directory. App `data/` isolation was verified from the live `logs` GoAccess namespace plus Landlock policy on 2026-07-05; static runtime directory scope is covered by detector policy tests.
- [x] App cannot see host PIDs through `/proc`.
- [x] App cannot see sibling app PIDs through `/proc`.
- [ ] App cannot bind unassigned TCP ports.
- [x] Static apps cannot make outbound network connections.
- [x] Executable apps are explicitly allowed outbound network connections.

## Non-goals for minimal posture

- [x] Do not require full container image lifecycle.
- [x] Do not require Kubernetes-style orchestration.
- [x] Do not require microVM isolation by default.
- [x] Do not require per-app host UIDs for the current baseline.
- [x] Do not require per-app systemd transient units unless needed for cgroups/accounting.
