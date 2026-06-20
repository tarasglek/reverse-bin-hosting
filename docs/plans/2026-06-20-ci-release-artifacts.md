# CI Release Artifacts Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make GitHub Actions build Debian packages and attach those CI-built artifacts to tagged GitHub releases.

**Architecture:** Extend `.github/workflows/package.yml` so normal pushes/PRs build and upload package artifacts, while tag pushes create/update a release and upload the CI-produced `.deb`, `.buildinfo`, and `.changes` files. Bump `debian/changelog` for a new release tag so the attached package version matches the tag.

**Tech Stack:** GitHub Actions, `actions/upload-artifact`, `softprops/action-gh-release`, Debian packaging, GNU Make.

---

### Task 1: Update package workflow

**Files:**
- Modify: `.github/workflows/package.yml`

**Steps:**
1. Add `permissions: contents: write`.
2. Add tag trigger `tags: ['v*']` under `push`.
3. Add an artifact upload step for `../reverse-bin*.deb`, `../reverse-bin*.buildinfo`, and `../reverse-bin*.changes`.
4. Add a release upload step gated by `startsWith(github.ref, 'refs/tags/')`, using `softprops/action-gh-release@v2` with the same files.

### Task 2: Bump Debian changelog

**Files:**
- Modify: `debian/changelog`

**Steps:**
1. Prepend `0.0.0-12` release entry describing CI-built release artifacts.
2. Use the current date.

### Task 3: Verify locally

**Commands:**
- `make tests`
- `make deb`
- `git diff --check`

Expected: all pass and package `../reverse-bin_0.0.0-12_amd64.deb` exists.

### Task 4: Commit, tag, push

**Commands:**
- Commit with `ci: attach dpkg artifacts from releases`.
- Tag `v0.0.0-12`.
- Push `master` and `v0.0.0-12`.

### Task 5: Babysit CI release

**Commands:**
- `gh run list --repo tarasglek/reverse-bin-hosting --limit 5`
- `gh run watch <run-id> --repo tarasglek/reverse-bin-hosting --exit-status`
- `gh release view v0.0.0-12 --repo tarasglek/reverse-bin-hosting --json assets,url`

Expected: CI succeeds and the release contains CI-built package artifacts.
