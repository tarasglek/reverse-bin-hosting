# Caddy Plugin Workflow Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build the packaged Caddy binary using the Caddy plugin workflow and hard-code the current stable caddy-reverse-bin release.

**Architecture:** Replace the local source import build with `xcaddy build --with github.com/tarasglek/reverse-bin=github.com/tarasglek/caddy-reverse-bin@v0.2.0`. Keep the runtime binary path and Caddyfiles unchanged.

**Tech Stack:** Go modules, Caddy, xcaddy, Debian packaging.

---

### Task 1: Update build commands

**Files:**
- Modify: `Makefile`
- Modify: `debian/rules`
- Modify: `go.mod`
- Modify: `README.md`

**Steps:**
1. Change `Makefile` build target from `go build ./cmd/caddy` to `xcaddy build --output $(CADDY_BIN) --with github.com/tarasglek/reverse-bin=github.com/tarasglek/caddy-reverse-bin@v0.2.0`.
2. Change `debian/rules` similarly for `build/reverse-bin-caddy`.
3. Remove the local `replace github.com/tarasglek/reverse-bin => ../caddy-reverse-bin` from `go.mod` and remove the obsolete custom Caddy main package.
4. Update README relationship text to mention the hard-coded release.

### Task 2: Verify

**Steps:**
1. Run `make build`.
2. Confirm `list-modules` includes `http.handlers.reverse-bin`.
3. Run `go test ./...`.
