# Reverse-Bin Apps ZFS Migration Plan

> Planning only. Do not execute migration steps without explicit approval.

**Goal:** Move `/var/lib/reverse-bin/apps` onto a ZFS filesystem dataset (candidate `zroot/apps`), preserving the `/home/taras/smallweb` idmapped bind view, app state, and rollback path. Do not use a zvol, symlink, or change application paths.

**Required properties:** Explicitly set `dedup=on` and `compression=zstd-19`. Do not make dedup contingent on the estimate. Preserve POSIX ACLs, xattrs, numeric ownership, modes, symlinks, hardlinks, and sparse files during tar copies.

## Checklist

- [ ] **1. Preflight.** Confirm `zroot` is healthy and has room for the staged copy and retained source; record current mounts, source snapshot/backup availability, service health, numeric `reverse-bin` UID/GID, and current `/etc/fstab` idmap (`u:113:1000:1,g:122:1000:1`). Check actual systemd mount ordering: ZFS mount before `home-taras-smallweb.mount`, which must precede `reverse-bin.service`. Identify independent writers (timers, deploy hooks, databases). Keep secrets out of notes. Do not upgrade the pool.

- [ ] **2. Estimate whole-file duplicates (read-only).** Host has `fclones 0.35.0`; `fclones group --help` confirms `--format json` and recursive scanning. Run:
  ```sh
  fclones group --format json --hidden --no-ignore /var/lib/reverse-bin/apps
  ```
  Read `header.stats.redundant_file_size` in the JSON as potential bytes saved by eliminating extra copies of identical whole files (or the default report's `Redundant` total). This is a practical estimate, not exact ZFS block-dedup savings or compression prediction; partial-block matches and compression are not measured. Include the scan time in planning, and discount/ignore transient files such as tmp data or logs backups when interpreting it. No disposable datasets or benchmark matrix is needed.

- [ ] **3. Create target and stage-copy.** Reconfirm free space and property support, then create a filesystem dataset with an isolated temporary mountpoint. Set `dedup=on` and `compression=zstd-19` explicitly; preserve compatible POSIX ACL/xattr support. Keep the source mounted and untouched. As root, an online initial tar pre-copy may reduce downtime:
  ```sh
  set -o pipefail
  tar --create --file=- --directory=/var/lib/reverse-bin/apps --numeric-owner --acls --xattrs --xattrs-include='*' --sparse . \
    | tar --extract --file=- --directory=<staging-mount> --numeric-owner --same-owner --same-permissions --acls --xattrs --xattrs-include='*' --sparse
  ```
  Confirm GNU tar support for these options and check both pipeline exit statuses. Tar preserves symlinks and hardlinks by default. Treat this pass as an inconsistent pre-copy only.

- [ ] **4. Quiesce and final-copy.** Schedule a short maintenance window. Stop `reverse-bin.service` cleanly and confirm Caddy, detector, and app subprocesses have exited; stop/quiesce all identified external writers. Use each database's supported clean shutdown/checkpoint or consistent-backup procedure. While the source is static, perform the final tar copy/reconciliation, account for removed/renamed source paths, and verify source vs staged file lists, content, numeric owners/modes, ACLs/xattrs, and database integrity where applicable. Check tar exit statuses and warnings. Do not delete or overwrite the source.

- [ ] **5. Cut over, verify, retain rollback.** Preserve the old tree at a dated sibling path on the old filesystem, then mount the ZFS dataset at `/var/lib/reverse-bin/apps`; do not expose an empty root if mounting fails. Keep `/home/taras/smallweb` as the same idmapped bind view with its existing UID/GID mapping. Confirm `findmnt` shows the new dataset and idmapped bind, service access to app data/logs/SOPS files, boot ordering, and writable Caddy access log before starting the service. Check service/journal health and representative static, executable, and database-backed app workflows. If checks fail, stop writers/service and restore the old tree and mount arrangement before restarting. Retain the old tree and available pre-cutover snapshot/backup through the rollback window; **do not delete source data until the user approves**.

## Host observations

- Existing app tree is on `zroot/ROOT/debian`; `/home/taras/smallweb` is its bind/idmap view. `reverse-bin.service` uses canonical `/var/lib/reverse-bin/apps` paths.
- `/home/taras/.cache` uses `zstd-19` and `dedup=on`, but its compression/dedup ratio is not predictive of app data.
- Service was live during planning and app data includes mutable state/DBs. A consistent final copy requires quiescing all writers; successful tar exit alone does not establish database consistency.
