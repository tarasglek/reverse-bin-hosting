# Static Caddy Unix Socket Design + Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement task-by-task.

**Goal:** Static `index.html` apps use Unix socket, not child TCP port.

**Why:** Static app need file reads + socket accept only. No outbound net. No TCP bind. Less port race. Smaller attack surface.

**Design:** Detector keeps nested `reverse-bin-caddy file-server`. Static transport is always Unix socket under reverse-bin runtime dir: `/run/reverse-bin/static-apps/app-<appdirhash>/reverse-bin.sock`, unless explicit `SOCKET_PATH` overrides for non-static apps only. Detector emits `ReverseProxyTo=unix//run/reverse-bin/static-apps/app-<hash>/reverse-bin.sock`. Child Caddy launches with `--listen unix///run/reverse-bin/static-apps/app-<hash>/reverse-bin.sock`. Static TCP config is rejected. reverse-bin creates parent dir and removes socket via one shared cleanup helper before launch, on stop, and on unhealthy restart.

**Stack:** Go detector, Caddy file-server, landrun, Markdown docs.

---

## Current facts

- POC works:
  ```sh
  reverse-bin-caddy file-server --listen unix///tmp/app/data/reverse-bin.sock --root /tmp/app
  curl --unix-socket /tmp/app/data/reverse-bin.sock http://localhost/
  ```
- POC also works under `landrun` with no `--bind-tcp`, when socket parent dir is writable.
- Current detector blocks static `SOCKET_PATH`:
  `static file server does not support SOCKET_PATH`
- Caddy supports it. Detector stale.

---

## Desired behavior

1. Static app, no env → Unix socket `/run/reverse-bin/static-apps/app-<appdirhash>/reverse-bin.sock`.
2. Static app, `SOCKET_PATH=...` → reject; static sockets are reverse-bin-managed only.
3. Static app, any TCP config (`REVERSE_BIN_PORT`, `REVERSE_BIN_HOST`, `LISTEN`) → reject.
4. Absolute `SOCKET_PATH` → reject for other app kinds as before.
5. Deno → still TCP-only.
6. Python → unchanged Unix default under app `data/`.
7. Static sandbox → never `--bind-tcp`; grant rw only to static runtime socket dir.

---

## Code plan

### 1. Tests first

File: `../reverse-bin-detector/internal/detector/detector_test.go`

Add/update cases:

- `index.html`, empty env → proxy starts `unix/`, contains `/run/reverse-bin/static-apps/app-`, ends `/reverse-bin.sock`, command has `--listen unix///run/reverse-bin/static-apps/app-.../reverse-bin.sock --root .`
- `dist/index.html`, empty env → same runtime socket, command has `--root dist`
- `index.html` + `SOCKET_PATH=data/static.sock` → error; static sockets are reverse-bin-managed only
- `index.html` + `REVERSE_BIN_PORT=8080` → error; static TCP forbidden
- `index.html` + `LISTEN=127.0.0.1:8080` → error; static TCP forbidden
- `index.html` + `REVERSE_BIN_HOST=127.0.0.1` → error; static TCP forbidden

Run:

```sh
cd ../reverse-bin-detector
go test ./internal/detector ./cmd/reverse-bin-detector
```

Expect fail before code change.

### 2. Detector change

File: `../reverse-bin-detector/internal/detector/detector.go`

In `resolveTransport`, reject all static explicit transport config:

```go
if kind == staticApp {
    if cfg.SocketPath != nil || hasTCPConfig(cfg) {
        return transport{}, nil, fmt.Errorf("static file server only supports reverse-bin-managed Unix sockets")
    }
    dir := staticRuntimeDir(appDir)
    path := filepath.Join(dir, "reverse-bin.sock")
    return transport{kind: "unix", proxy: "unix/" + path, socketDir: dir}, map[string]string{}, nil
}
```

Keep Python default separate:

```go
if !hasTCPConfig(cfg) && kind == pythonApp {
    path := filepath.Join(appDir, "data", "reverse-bin.sock")
    return transport{kind: "unix", proxy: "unix/" + path}, map[string]string{KeySocketPath: filepath.Join("data", "reverse-bin.sock")}, nil
}
```

Add deterministic dir helper using app dir hash:

```go
func staticRuntimeDir(appDir string) string {
    sum := sha256.Sum256([]byte(filepath.Clean(appDir)))
    return filepath.Join("/run/reverse-bin/static-apps", "app-"+hex.EncodeToString(sum[:])[:16])
}
```

Add `socketDir string` or equivalent to transport so sandbox can grant exact dir.

In `commandFor`, allow static Unix:

```go
case staticApp:
    if tr.kind == "unix" {
        path := strings.TrimPrefix(tr.proxy, "unix/")
        return []string{"reverse-bin-caddy", "file-server", "--listen", "unix//" + path, "--root", a.root}, nil
    }
    return []string{"reverse-bin-caddy", "file-server", "--listen", tr.listen, "--root", a.root}, nil
```

Reason: `tr.proxy = unix/ + /abs/path`; Caddy wants `unix///abs/path`.

For static Unix transport, runtime sandbox must include:

```go
--rw <tr.socketDir>
```

and no `--bind-tcp`.

### 3. E2E update

File: `../reverse-bin-detector/cmd/reverse-bin-detector/e2e_test.go`

Static app output should assert:

- `ReverseProxyTo` starts `unix/`
- contains `/run/reverse-bin/static-apps/app-`
- suffix `/reverse-bin.sock`
- executable has `reverse-bin-caddy file-server`
- executable has `--listen unix//`

Run:

```sh
cd ../reverse-bin-detector
go test ./...
```

Expect pass.

---

### 4. caddy-reverse-bin socket dir + unified cleanup

File: `../caddy-reverse-bin/reverse-bin.go`

Add helper, use everywhere socket removal happens:

```go
func unixSocketPath(addr string) (string, bool) {
    if !isUnixUpstream(addr) {
        return "", false
    }
    return strings.TrimPrefix(addr, "unix/"), true
}

func removeUnixSocket(addr string) error {
    socketPath, ok := unixSocketPath(addr)
    if !ok {
        return nil
    }
    if err := os.Remove(socketPath); err != nil && !os.IsNotExist(err) {
        return fmt.Errorf("failed to remove unix socket %s: %w", socketPath, err)
    }
    return nil
}
```

Before launch, replace inline `os.Remove(socketPath)` with `removeUnixSocket(cfg.ReverseProxyTo)`.

In unhealthy restart path, replace inline remove with same helper.

In `stopBackend`, after process exits or after kill wait succeeds, call same helper:

```go
defer func() { _ = removeUnixSocket(rb.config.ReverseProxyTo) }()
```

Also create parent dir before launch for reverse-bin runtime sockets:

```go
if socketPath, ok := unixSocketPath(cfg.ReverseProxyTo); ok && strings.HasPrefix(socketPath, "/run/reverse-bin/static-apps/") {
    if err := os.MkdirAll(filepath.Dir(socketPath), 0o700); err != nil {
        return nil, err
    }
}
```

Tests:

- pre-existing socket removed before launch/config resolve
- socket removed on `stopBackend`
- helper ignores non-Unix upstream
- helper ignores missing socket

---

## Docs plan

### 4. `SECURITY-POSTURE.md`

Update network policy:

- Static apps always run nested Caddy over Unix socket under `/run/reverse-bin/static-apps/app-<hash>/`.
- Static apps never use TCP listeners.
- Static apps reject TCP env config.
- Static apps need no TCP bind permission.
- Static apps need no outbound network for normal serving.
- TCP runtimes still need per-transport policy.
- Deno still TCP-only.

Checklist final state:

```md
- [x] Static website apps use nested `reverse-bin-caddy file-server` over a Unix socket under `/run/reverse-bin/static-apps/app-<hash>/`.
- [x] Static website apps require no TCP bind permission in their runtime sandbox.
- [x] Apps may use Unix sockets under app `data/` when runtime/app config supports them.
- [ ] App cannot make outbound network connections unless explicitly allowed by policy.
```

Keep last unchecked until all runtimes covered.

### 5. `README.md`

Add concise rule:

```md
Static `index.html` and `dist/index.html` apps are served by nested Caddy over `/run/reverse-bin/static-apps/app-<hash>/reverse-bin.sock`. Static apps never listen on TCP; TCP listener env config is rejected.
```

Keep `REVERSE_BIN_PORT` docs, but say TCP command apps use it.

### 6. `skills/reverse-bin-web-apps/SKILL.md`

Update:

- static apps default Unix socket
- Caddy file-server supports `--listen unix///abs.sock`
- Unix socket transports need no TCP bind permission

### 7. `../reverse-bin-detector/docs/python-detector-test-matrix.md`

Replace stale claim:

```md
Deno/static TCP-only providers reject socket transport.
```

With:

```md
Deno remains TCP-only. Static apps always use reverse-bin-managed Unix socket transport through Caddy file-server and reject TCP listener config.
```

### 8. `../reverse-bin-detector/docs/plans/2026-06-20-go-landlock-detector.md`

Historical doc. Do not rewrite checkboxes. Add follow-up note:

```md
2026-07-05 follow-up: Caddy file-server supports `--listen unix///path.sock`. Static apps should always use reverse-bin-managed Unix sockets under `/run/reverse-bin/static-apps/app-<hash>/`, reject TCP listener config, and never need static runtime `--bind-tcp`.
```

---

## Verification

Run detector tests:

```sh
cd ../reverse-bin-detector
go test ./...
```

Run stale-doc grep:

```sh
cd /home/taras/Documents/reverse-bin-hosting
rg -n "static.*TCP-only|Deno/static|static.*bind-tcp|Static app.*detector-selected TCP" README.md SECURITY-POSTURE.md skills/reverse-bin-web-apps/SKILL.md ../reverse-bin-detector/docs
```

Expect no stale unqualified claims.

Manual smoke:

```sh
app=$(mktemp -d)
mkdir -p "$app/data"
printf '<h1>ok</h1>\n' > "$app/index.html"
sock="$app/data/reverse-bin.sock"
./build/reverse-bin-caddy file-server --listen "unix//$sock" --root "$app" &
pid=$!
for i in $(seq 1 50); do [ -S "$sock" ] && break; sleep 0.1; done
curl --fail --unix-socket "$sock" http://localhost/ | grep ok
kill "$pid"
rm -rf "$app"
```

---

## Rollback

If packaged runtime breaks:

1. Revert whole feature if static Unix broken.
2. Do not silently fall back to static TCP.
3. Docs say: static app unavailable until Unix socket issue fixed.
