# Per-app SSH Sessions Implementation Plan

**Goal:** `ssh -i todo.pem reverse-bin@host` opens an interactive shell in the `todo` app's production sandbox; `ssh -i todo.pem reverse-bin@host CMD` runs one command there. One key maps to one app.

**Architecture:** sshd binds each key to its app with a per-key `command="/usr/lib/reverse-bin/rb-ssh <app>"` in `~reverse-bin/.ssh/authorized_keys`. `rb-ssh` is a symlink to `reverse-bin-detector`; the detector dispatches on argv[0]. `rb-ssh` is also the `reverse-bin` login shell, because sshd runs forced commands as `$SHELL -c CMD` and `nologin` cannot run them. As a shell it only accepts `-c "<path>/rb-ssh <app>"`, so a key line without `command=`, `su`, or `sudo -i` cannot get a general shell. `rb-ssh` execs the existing `--as-app` sandbox (Landlock + namespaces).

**Guarantee:** a per-app key grants an interactive session inside that app's sandbox under the shared `reverse-bin` UID, including the app's decrypted secrets. It is an app sandbox, not a tenant boundary. Anyone running unsandboxed code as `reverse-bin` can reach every app's secrets, so the sandbox must not expose unsandboxed escape primitives such as the Caddy admin API.

**Tech Stack:** Go (reverse-bin-detector), OpenSSH, Caddyfile, Debian maintainer scripts.

**Review:** Fable 5.1 systems and security reviews, merged into this KISS design. Rejected: `ForceCommand` + `ExposeAuthInfo` + re-parsing `authorized_keys` (a second parser can disagree with sshd); keeping `nologin` (cannot run forced commands, `session.c:1673`).

---

- [x] Task 1: Disable the Caddy admin API (hosting; blocker)
  - Files: `packaging/debian/Caddyfile.acme`, `packaging/debian/Caddyfile.http-only`, `scripts/check-caddy-listeners.sh`
  - Test first: assert adapted JSON has `admin.disabled == true` for both configs.
  - Verify RED: `make build && ./scripts/check-caddy-listeners.sh` fails on admin.
  - Implement: `admin off` in both global option blocks. Nothing in the repo uses the admin API.
  - Verify GREEN: same command passes.

- [x] Task 2: `--as-app` execs the sandbox (detector)
  - Files: `internal/detector/detector.go`, tests.
  - Test first: e2e test sends SIGHUP to the `--as-app` process and asserts the sandboxed child is gone.
  - Verify RED: the child survives (Go parent dies, `unshare` and child remain).
  - Implement: `syscall.Exec` the plan executable after `chdir`; keep plan generation in the helper process.
  - Verify GREEN: `make check`.

- [x] Task 3: `rb-ssh` mode (detector)
  - Files: `cmd/reverse-bin-detector/main.go`, new `internal/sshgate`, tests.
  - Accepted invocations: `rb-ssh <app>` and `rb-ssh -c "<dir>/rb-ssh <app>"`; everything else is refused, including a login shell (`-rb-ssh`).
  - App name: `[A-Za-z0-9][A-Za-z0-9._-]*`; resolved directory must stay under the apps root.
  - Command: no `SSH_ORIGINAL_COMMAND` → `bash -i` (not `-l`: `/etc/profile` would reset `PATH`); set → `sh -c "$SSH_ORIGINAL_COMMAND"`; `sftp-server`/`internal-sftp` → refuse.
  - Env: set `PATH=/usr/lib/reverse-bin:/usr/bin:/bin`, `SOPS_AGE_KEY_FILE=/var/lib/reverse-bin/keys/age.key`; pass `TERM`, `COLORTERM`, `LANG`, `LC_ALL` into the sandbox.
  - Paths are link-time overridable (`-ldflags -X`) for tests only; not environment-controlled.
  - Verify: unit tests for parsing; e2e test with a binary named `rb-ssh`; `make check`.

- [x] Task 4: Packaging (hosting)
  - Files: `debian/links`, `debian/postinst`, `debian/postrm`, `packaging/debian/sshd_config.d/reverse-bin.conf`, `debian/install`.
  - `debian/links`: `usr/lib/reverse-bin/rb-ssh` → `reverse-bin-detector`.
  - sshd drop-in `/etc/ssh/sshd_config.d/reverse-bin.conf`: `Match User reverse-bin` with `AuthenticationMethods publickey`, `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `DisableForwarding yes`, `PermitTTY yes`. Included-file `Match` scope ends at end of file (`servconf.c:2203-2219`). The package never reloads sshd.
  - postinst: `add-shell`; if shell is `/usr/sbin/nologin`, `usermod -s /usr/lib/reverse-bin/rb-ssh`; create `home/.ssh` 0700. Never create or rewrite `authorized_keys`.
  - postrm (`remove`/`purge`): `remove-shell`; revert shell to `nologin` if it is still `rb-ssh`.
  - Detector pin bump waits for a detector release containing Tasks 2-3. Until then `rb-ssh` fails closed (old detector rejects `-c`).
  - Verify: `make tests`; `sh -n` on maintainer scripts; `dpkg-buildpackage` if available.

- [x] Task 5: Docs (hosting)
  - Files: `README.md` "Interactive sandbox shells", `SECURITY-POSTURE.md`.
  - Add the key-line format, a one-line `authorized_keys` append recipe, the guarantee above, and the sftp refusal.

- [x] Task 6: End-to-end with a real sshd (no root)
  - Run the extracted Debian `sshd` 10.0 as the current user on `127.0.0.1:2222` with a test `authorized_keys` line pointing at `rb-ssh`.
  - Check: interactive PTY shell lands in the app with `HOME=<app>/data`; one-shot command and exit status; source read-only; sftp refused; closing the session leaves no sandbox processes.
  - The test user's login shell is bash, so the `rb-ssh -c` login-shell path is covered by a container install where `rb-ssh` is the real login shell.

Out of scope: OpenBSD packaging.

## Results (2026-10-13)

- Detector v0.1.14 ships `rb-ssh` and exec-based `--as-app`; see its release notes for detector-side details (including dying with the sshd session when there is no PTY).
- No `rb-ssh-key` helper; the README has a one-line `printf | sudo -u reverse-bin tee -a` recipe instead.
- Real sshd (Debian 10.0p1, unprivileged): one-shot exit status, PTY shell, per-key app mapping, unknown key denied, sftp/scp and port forwarding refused, no survivors after client kill with or without a PTY.
- Container (debian:trixie, built .deb), 22/22 checks: shell switched and in `/etc/shells`, `.ssh` 0700, sshd `Match` applies only to `reverse-bin`, sessions sandboxed with per-app secrets, key line without `command=` refused, `su`/`su -` refused, `runuser`/`sudo -u` unaffected, README recipes work, remove reverts shell, reinstall keeps `authorized_keys`. Docker needed `systempaths=unconfined` for `unshare --mount-proc`.
- With detector v0.1.13 behind the `rb-ssh` symlink, both invocation forms are refused (fails closed).
- Pre-existing, not changed: postinst fails where `systemctl` exists without systemd PID 1 (containers).
