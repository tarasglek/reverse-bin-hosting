# Release Main Deb Only Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Future GitHub releases should attach only the installable main Debian package.

**Architecture:** Keep CI building the package as before, but collect/upload/release only `../reverse-bin_*_amd64.deb` while excluding dbgsym, buildinfo, and changes files.

**Tech Stack:** GitHub Actions, Debian packaging.

---

### Task 1: Restrict release artifacts

**Files:**
- Modify: `.github/workflows/package.yml`

**Steps:**
1. Change the artifact collection step to copy only `../reverse-bin_[0-9]*_amd64.deb` into `dist/`.
2. Keep upload-artifact and release attachment using `dist/*`.
3. Verify workflow YAML and local packaging still works.

### Task 2: Verify and commit

**Commands:**
- `make tests`
- `make deb`
- `git diff --check`
- Commit and push.
