# Security Posture Checklist

Reverse-bin runs untrusted or semi-trusted apps from `/var/lib/reverse-bin/apps`. Default posture: minimal host access, explicit app access, layered Linux isolation.

_Last checked against package state on 2026-07-05: `reverse-bin-detector 0.1.11`, package `0.0.3-1`, and `debian/reverse-bin.service`._

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
- [x] Uses explicit launch policy for network bind permissions.
- [x] Gives each launched app its own PID namespace.
- [x] Mounts a private `/proc` matching that PID namespace.
- [x] Prevents apps from seeing the host process list through `/proc`.
- [x] Prevents apps from seeing sibling app processes through `/proc`.
- [x] Adds IPC namespace isolation.
- [x] Adds UTS namespace isolation.
- [x] Uses a shared host `reverse-bin` UID intentionally for app processes.
- [x] Uses `--map-current-user` so app namespaces map to the service UID, not root.
- [x] Treats per-app host UIDs as potential defense-in-depth, not baseline isolation.

Current wrapper shape returned by `reverse-bin-detector 0.1.11`:

```sh
unshare \
  --map-current-user \
  --pid --fork --mount-proc \
  --ipc --uts --kill-child -- \
  landrun ... app command ...
```

Apps intentionally run under the shared host `reverse-bin` UID. `--map-current-user` maps the app namespace to that service UID instead of root, so existing `reverse-bin`-owned `data/` writes continue to work.

Isolation is provided by Landlock path/network rules plus per-app PID/private `/proc`, IPC, and UTS namespaces, not by Unix user separation. Apps cannot enumerate host or sibling processes through `/proc`, cannot access paths outside their Landlock allowlist, and cannot write outside their own `data/` directory.

Per-app host UIDs are potential defense-in-depth only. They would not add protection under the current allowlist and namespace policy, so they are not part of the baseline.

## Filesystem policy

Current detector policy for launched apps:

- [x] App source is read/execute-only in the Landlock sandbox (`--rox <app-dir>`).
- [x] App `data/` is read/write (`--rw <app-dir>/data`).
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
- [x] `/dev` is read/write as currently required by common runtimes.

Observed policy shape:

```sh
landrun \
  --rox /bin,/usr,/lib,/lib64,/proc,/sys/fs/cgroup \
  --ro /etc \
  --rw /dev \
  --rw <app-dir>/data \
  --rox <app-dir> \
  --bind-tcp <assigned-port> \
  ...
```

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

Default network policy depends on app type. Static website apps run as a nested `reverse-bin-caddy file-server`. That process only needs to read static files and listen on its assigned backend port, so it uses the most restricted listen-only network policy: Landlock `--bind-tcp <assigned-port>`. Other app runtimes currently use unrestricted network access. The policy reverse-bin wants is narrower: restrict listen/bind to the assigned app port, but allow outbound connects.

Current tools do not expose that policy directly. Deno has `--allow-net`, which covers both listen and connect. landrun has `--bind-tcp <port>`, which also restricts connects, or `--unrestricted-network`, which also allows arbitrary binds. Reverse-bin therefore uses unrestricted network for non-static runtimes until bind-only network handling is available.

Landlock also enforces filesystem access: app source is read/execute-only, app `data/` is read/write, `/etc` is read-only, required runtime paths are read/execute-only, and reverse-bin keys and sibling app state are outside the allowlist.

- [x] Packaged HTTP-only Caddy mode binds only `127.0.0.1:${REVERSE_BIN_HTTP_PORT:-7777}`.
- [x] ACME mode uses Caddy-managed HTTPS with on-demand TLS and an ask endpoint restricted to the configured domain suffix.
- [x] Apps share the host network namespace intentionally.
- [x] Static website apps use nested `reverse-bin-caddy file-server` with Landlock `--bind-tcp <assigned-port>`.
- [x] Non-static runtimes use unrestricted network for compatibility.
- [x] Landlock restricts filesystem access to app source, app `data/`, and required runtime paths.
- [x] Apps may use Unix sockets under app `data/` when runtime/app config supports them.
- [ ] Potential hardening: add bind-only network handling so non-static runtimes can restrict listen ports while keeping outbound connects unrestricted.

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
- [x] App cannot write outside its `data/` directory. Verified from live `logs` GoAccess app namespace plus app Landlock policy on 2026-07-05.
- [x] App cannot see host PIDs through `/proc`.
- [x] App cannot see sibling app PIDs through `/proc`.
- [ ] App cannot bind unassigned TCP ports.
- [ ] App cannot make outbound network connections unless explicitly allowed by policy.

## Non-goals for minimal posture

- [x] Do not require full container image lifecycle.
- [x] Do not require Kubernetes-style orchestration.
- [x] Do not require microVM isolation by default.
- [x] Do not require per-app host UIDs for the current baseline.
- [x] Do not require per-app systemd transient units unless needed for cgroups/accounting.
