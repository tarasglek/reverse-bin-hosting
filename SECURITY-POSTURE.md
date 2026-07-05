# Security Posture Checklist

Reverse-bin runs untrusted or semi-trusted apps from `/var/lib/reverse-bin/apps`. Default posture: minimal host access, explicit app access, layered Linux isolation.

## Goals

- [ ] Protect host from app code.
- [ ] Protect apps from each other.
- [ ] Protect operator/user homes from reverse-bin Caddy and app subprocesses.
- [ ] Keep app ergonomics: app directory plus `data/` writable state.
- [ ] Prefer kernel-native, minimal, auditable primitives over heavy orchestration.

## Systemd service baseline

`reverse-bin.service` must harden the outer Caddy/reverse-bin process. This protects host paths before any per-app sandbox runs.

Required by default:

- [x] Set `ProtectHome=yes`.
- [ ] Set `NoNewPrivileges=yes`.
- [ ] Set `PrivateTmp=yes`.

Recommended next hardening:

- [ ] Set `ProtectSystem=strict`.
- [ ] Set `ReadWritePaths=/var/lib/reverse-bin /run/reverse-bin`.

### `ProtectHome=yes`

- [x] Require `ProtectHome=yes` in packaged systemd unit.
- [x] Confirm `/home` is inaccessible to `reverse-bin.service`.
- [x] Confirm `/root` is inaccessible to `reverse-bin.service`.
- [x] Confirm `/run/user` is inaccessible to `reverse-bin.service`.
- [ ] Document that this blocks outer Caddy and detector from reading operator home directories, SSH keys, shell history, browser profiles, and user config by default.
- [ ] Document that app-specific writable state must use `/var/lib/reverse-bin/apps/<app>/data`, not `/home`.

`ProtectHome=yes` is service-wide systemd isolation. It applies to reverse-bin and inherited app subprocesses unless the app launcher creates a different mount namespace.

## Per-app isolation

Per-app isolation belongs in `reverse-bin-detector` or its launch wrapper, not only in systemd. Systemd isolates the reverse-bin service as a whole; it does not give each app its own PID namespace unless each app becomes a separate systemd unit.

Current baseline:

- [x] Use `landrun` for Landlock filesystem policy.
- [x] Give apps read access to app source.
- [x] Give apps write access to app `data/`.
- [x] Give apps only required runtime/system paths.
- [x] Use explicit launch policy for network bind/connect permissions.

Required direction:

- [ ] Give each app its own PID namespace.
- [ ] Give each app private `/proc` matching that PID namespace.
- [ ] Prevent apps from seeing host process list.
- [ ] Prevent apps from seeing sibling app processes.
- [ ] Add IPC namespace isolation.
- [ ] Add UTS namespace isolation.
- [ ] Keep Landlock/landrun for filesystem and network allowlists.

Minimal likely shape:

```sh
bwrap \
  --unshare-user \
  --unshare-pid \
  --unshare-ipc \
  --unshare-uts \
  --proc /proc \
  --die-with-parent \
  -- \
  landrun ... app command ...
```

Exact wrapper may differ, but policy stays: namespaces for process view, Landlock for file/network access.

## Filesystem policy

- [ ] App source is read-only.
- [ ] App `data/` is read-write.
- [ ] Reverse-bin keys are inaccessible to apps.
- [ ] `/home` is inaccessible by default.
- [ ] `/root` is inaccessible by default.
- [ ] `/run/user` is inaccessible by default.
- [ ] Runtime binaries under `/usr/lib/reverse-bin` are executable/read-only.
- [ ] Config under `/etc/reverse-bin` is read-only.

## Secrets

- [ ] Systemd sets `SOPS_AGE_KEY_FILE=/var/lib/reverse-bin/keys/age.key` for the service.
- [ ] Detector may use key to decrypt `secrets.enc.json`.
- [ ] Child apps receive decrypted environment values only.
- [ ] Child apps do not receive `SOPS_AGE_KEY_FILE` unless explicitly configured by app env.
- [ ] Child apps cannot read `/var/lib/reverse-bin/keys`.

## Network policy

- [ ] Apps bind only assigned localhost TCP port or app Unix socket.
- [ ] Prefer Unix sockets under app `data/` when runtime supports them.
- [ ] Make outbound network access explicit policy.
- [ ] Helper services needing extra listeners use Unix sockets, not extra TCP ports.

## Verification commands

Systemd/service checks:

```sh
systemd-analyze security reverse-bin.service
sudo systemctl show reverse-bin.service -p ProtectHome -p NoNewPrivileges -p PrivateTmp -p ProtectSystem -p ReadWritePaths
```

Access checks:

```sh
# reverse-bin service must not access /home
sudo -u reverse-bin test ! -r /home || false
```

App isolation checks:

- [ ] App cannot read `/home`.
- [ ] App cannot read `/var/lib/reverse-bin/keys/age.key`.
- [ ] App cannot write outside its `data/` directory.
- [ ] App cannot see host PIDs through `/proc`.
- [ ] App cannot see sibling app PIDs.
- [ ] App cannot bind unassigned TCP ports.

## Non-goals for minimal posture

- [ ] Do not require full container image lifecycle.
- [ ] Do not require Kubernetes-style orchestration.
- [ ] Do not require microVM isolation by default.
- [ ] Do not require per-app systemd transient units unless needed later for cgroups/accounting.
