# Reverse-Bin Apps ZFS Migration Plan

> **For Claude:** This is a planning document only. Do not execute migration steps without explicit approval.

**Goal:** Move `/var/lib/reverse-bin/apps` onto a dedicated ZFS filesystem dataset while preserving the editable idmapped view at `/home/taras/smallweb`, app state, and a rollback path.

**Architecture:** Use a ZFS filesystem dataset (candidate `zroot/apps`), not a block zvol: this is a mounted directory tree and needs ZFS file semantics, snapshots, and mount ordering. Keep `/var/lib/reverse-bin/apps` as the canonical app root so Caddy/detector paths remain unchanged; keep the existing bind/idmap mount to `/home/taras/smallweb`.

**Tech Stack:** OpenZFS 2.4.1 (Proxmox kernel module 2.4.2), GNU tar, systemd, reverse-bin/Caddy.

---

## Findings / sizing baseline

- `/var/lib/reverse-bin/apps` is currently on `zroot/ROOT/debian` (root filesystem dataset, inherited `compression=zstd`, `dedup=off`), not a separate dataset. The tree is exposed as `/home/taras/smallweb` by `/etc/fstab` bind mount with `X-mount.idmap=u:113:1000:1,g:122:1000:1`; do not replace this with a symlink or lose the idmap.
- `/home/taras/.cache` is a separate `zroot/cache` filesystem (`zstd-19`, `dedup=on`, `atime=off`, `recordsize=128K`, `acltype=posix`, `xattr=sa`), not a zvol. It reports logical 148G / referenced 81.7G (1.96x compressed). This is a precedent, not evidence that apps will achieve the same ratio.
- Read-only measurement: app tree is about **12.03 GB apparent** and **8.12 GB allocated by `du`** (including `logs.backup.20260621164300`). This is not a clean ZFS allocation baseline; it omits snapshot accounting and reflects current compression/dedup effects. The largest allocated app trees include `locker` 1.75 GB, `podcasts` 1.56 GB, `echoear` 1.42 GB, `chatcraft` 1.19 GB, and `podly-pure-podcasts` 419 MB. Re-measure per-app as root at implementation time and decide whether the stale logs backup belongs in the migration.
- The current app data shares the root filesystem's compression setting, so sizing the new dataset's actual savings requires a representative write test. `zroot` is ONLINE with mirror-0; `zpool list` reported 464G size, 307G allocated, 157G free, 66% capacity, pool dedup ratio 1.08x. `zroot/cache` reports `zstd-19` and dedup on; global RAM was 62 GiB and ARC about 25 GiB at inspection. Per user direction, the new apps dataset must explicitly use `dedup=on`; benchmark results estimate its benefit/cost, not whether to enable it. `zdb` is not installed/on PATH; check for the OpenZFS utility before relying on DDT breakdowns.
- Live reverse-bin is enabled/running, and had active `tesla-telemetry` and `pi-shared-provider` subprocesses at inspection. Other app subprocesses can start on requests, and Caddy writes `/var/lib/reverse-bin/apps/logs/caddy-logs/access.log`. Stop the service for the consistent final copy; separately check scheduled jobs, deploy hooks, and external writers.
- `reverse-bin.service` runs as `reverse-bin:reverse-bin`, uses canonical `/var/lib/reverse-bin/apps` paths, and is currently ordered after `home-taras-smallweb.mount`; that generated mount is ordered after `zfs-mount.service` and before reverse-bin. Confirm the resulting ZFS dataset mount is ready before the bind mount and service on boot. No applicable repository `AGENTS.md` was found.

## Plan

- [ ] 1. Preflight and record a recoverable baseline (read-only).
  - Confirm pool health/free space, `zfs version`, current snapshots, ZFS feature state, effective dataset properties, `zfs get`/`zpool list`, ARC/RAM, and that no pool upgrade is needed (do not upgrade the pool as part of this work).
  - As root, collect per-app apparent and allocated sizes (`du -sx --apparent-size -B1` and `du -sx -B1` per immediate child); include hidden files, ACLs/xattrs, hardlinks, sparse files and symlinks. Record file counts, owners/UID/GIDs, permissions, ACL/xattr presence, and `zfs list -t snapshot` for the source dataset. Identify and explicitly include/exclude the existing `logs.backup.*` tree.
  - Check `findmnt`, `systemctl cat/show reverse-bin.service home-taras-smallweb.mount`, `/etc/fstab`, live Caddy config/app-root references, direct writers and app-specific database engines. Capture current public app health and recent service logs. Do not print or store secrets in the report.
  - Gate: enough free capacity for staged copy plus an independent rollback copy/snapshot; all write paths, idmapping, and cutover/boot ordering understood.

- [ ] 2. Estimate compression and dedup savings before choosing properties.
  - First compute existing per-app/source `du` logical/apparent totals and source ZFS dataset logical/referenced/used/compressratio; `du` totals are not a substitute for ZFS block accounting. Use representative data from several largest apps and runtime state (including DB/media/cache files), not just source text.
  - Preferred measurement: create two disposable, isolated filesystem datasets on the same pool and write identical representative samples to both: candidate `compression=zstd-19,dedup=off` and `compression=zstd-19,dedup=on`. Compare `logicalreferenced`, `referenced`, `used`, `compressratio`, DDT size/dedup ratio, ARC/RAM, and write CPU; include shared assets and unique app data. This estimates benefit and cost; it does not gate the required production setting. Delete test datasets only after recording results. Do not toggle dedup on live data for a test.
  - Compare `zstd` and `zstd-19` samples for CPU and size. `zstd-19` is the literal maximum level supported here and matches cache precedent. Test it against ordinary `zstd`, then set the chosen level explicitly; do not use ambiguous `compression=on`.
  - Set production `dedup=on` per user direction, even if measured savings are small. Keep benchmark and runtime monitoring to quantify DDT/RAM, metadata, and write-path costs; report material risks before cutover. Existing pool dedup ratio 1.08x / cache results are not proof of app-data savings.

- [ ] 3. Decide destination dataset and mount semantics before making it.
  - Candidate filesystem: `zroot/apps`, mounted at `/var/lib/reverse-bin/apps`; do not use a zvol. Set `dedup=on` explicitly per user direction. Start with no quota/reservation unless sizing/operations establish one. Choose `compression=zstd-19` or the benchmark-supported zstd level; use `atime=off` only if app behavior tolerates it, and `recordsize=128K` pending DB-specific review. Preserve POSIX ACL and xattr support (`acltype=posix`, `xattr=sa` where compatible). Check parent inheritance, dataset feature compatibility, and ACL/idmap behavior first.
  - Keep service-visible owners as numeric `reverse-bin` UID/GID (confirm current numeric IDs immediately before migration). The current user-facing mount idmaps those IDs to `taras`; preserve exactly this mapping. Validate as both users. Do not recursively chown based on names from the idmapped view.
  - Verify boot: ZFS import/mount at `zfs-mount.service` must precede `/home/taras/smallweb` bind/idmap mount; that mount must precede `reverse-bin.service`. Add explicit systemd ordering only if generated/actual unit dependency inspection shows existing ordering is insufficient. Ensure Caddy's access-log target exists/writable after cutover.
  - Decide snapshot schedule/retention, replication/backup coverage, monitoring/alerts, and ownership of the old tree/rollback window. Take a pre-cutover source snapshot where possible; snapshots alone are not an independent backup.

- [ ] 4. Stage a tar copy without disturbing production.
  - Build the target mounted at a temporary staging mountpoint first; retain source unchanged. Use a root-run GNU tar stream with numeric IDs and metadata options, e.g. `tar --create --file=- --directory=/var/lib/reverse-bin/apps --numeric-owner --acls --xattrs --xattrs-include='*' --sparse --one-file-system . | tar --extract --file=- --directory=<staging-mount> --numeric-owner --same-owner --same-permissions --acls --xattrs --xattrs-include='*' --sparse`. Confirm GNU tar versions/options support ACLs, xattrs, sparse files; include SELinux labels only if the source actually uses them. Preserve symlinks/hardlinks (tar defaults), ownership, modes, ACLs, xattrs, and numeric IDs.
  - This initial online pass is only a pre-copy and is not consistent for changing files. Record the archive stream digest/manifest and errors, and inspect failed paths; do not claim database consistency based on a successful tar exit alone.

- [ ] 5. Quiesce writers and perform the final consistent copy.
  - Announce maintenance window; stop `reverse-bin.service` cleanly (`TimeoutStopSec=45s`); confirm Caddy/detector/app subprocesses exited. Stop or quiesce any independent app writers, deployment processes, timers, and database services. For each SQLite/DuckDB/other mutable DB, use its supported clean shutdown/checkpoint or documented consistent backup procedure before archiving. If a DB cannot be quiesced or backed up consistently, exclude it from live tar and use its documented backup/restore path.
  - Reconcile the staging tree from the now-static source with tar. Record `sha256sum` of deterministic sorted tar streams for source and staging, compare file lists and metadata, inspect tar warnings/exit status, and run available database integrity checks against the staged copy. No source deletion or overwrite during this step.

- [ ] 6. Cut over with immediate rollback available.
  - With reverse-bin still stopped, preserve the original tree under a dated sibling path on the old root dataset (do not delete it); switch the new filesystem dataset mountpoint to `/var/lib/reverse-bin/apps` and mount it. Do not expose an empty app root if mount fails. Keep `/home/taras/smallweb` bind/idmap mounted from the canonical path and verify its visible UID/GID and access.
  - Confirm `findmnt -T` shows the new ZFS dataset at `/var/lib/reverse-bin/apps` and the existing idmapped bind at `/home/taras/smallweb`; check systemd mount ordering and service access to app source, `data/`, logs and SOPS files. Start reverse-bin only after checks pass.

- [ ] 7. Verify, monitor, and retain rollback.
  - Compare file manifest/checksums, owners/modes, ACLs/xattrs, hardlink/symlink/sparse behavior; confirm app-root config and access-log path. Check `systemctl status`, `journalctl -u reverse-bin.service`, and public health endpoints for representative static, executable, database-backed, and largest apps. Check real app workflows and service logs; confirm no hidden write failures/permission errors. Observe ZFS `used`, `logicalreferenced`, `compressratio`, pool free space, CPU, ARC/memory, and latency under normal use.
  - Keep old tree untouched/read-only if practical, plus pre-cutover snapshot and backup, for an agreed rollback window. Do not delete the old tree until all checks pass, snapshots/backup are confirmed, and rollback window expires.
  - Rollback: stop reverse-bin and all writers; unmount the new dataset from the canonical path, restore its temporary mountpoint/state as needed, restore the preserved old directory to `/var/lib/reverse-bin/apps`, verify the idmapped bind mount and boot ordering, then start service and repeat health/log checks. Never roll back by overlaying old data onto a live mounted dataset.
