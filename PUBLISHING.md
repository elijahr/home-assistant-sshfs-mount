# Publishing Guide

This document outlines the steps to publish the SSHFS Mount add-on to GitHub.

## Pre-Publication Checklist

All files have been created and are ready for publication:

- [x] LICENSE (MIT)
- [x] .gitignore
- [x] repository.json
- [x] build.yaml
- [x] CHANGELOG.md
- [x] README.md (with installation instructions)
- [x] .pre-commit-config.yaml
- [x] .yamllint.yaml
- [x] .markdownlint.json
- [x] .github/workflows/builder.yaml
- [x] .github/workflows/lint.yaml
- [x] icon.png and logo.png
- [x] icon.svg and logo.svg (sources)
- [x] ICONS.md (customization instructions)

## Publishing Steps

### 1. Initialize Git Repository

```bash
cd /Users/elijahrutschman/Library/CloudStorage/MountainDuck-ha-addons/local/home-assistant-sshfs-mount
git init
git add .
git commit -m "Initial commit: SSHFS Mount add-on v1.0.15"
```

### 2. Create GitHub Repository

1. Go to https://github.com/new
2. Repository name: `home-assistant-sshfs-mount`
3. Description: "Mount remote SSH servers and share them via Samba in Home Assistant"
4. Public repository
5. **Do NOT** initialize with README, .gitignore, or license (we already have these)
6. Click "Create repository"

### 3. Push to GitHub

```bash
git remote add origin https://github.com/elijahr/home-assistant-sshfs-mount.git
git branch -M main
git push -u origin main
```

### 4. Create First Release

1. Go to https://github.com/elijahr/home-assistant-sshfs-mount/releases
2. Click "Create a new release"
3. Tag version: `v1.0.15`
4. Release title: `v1.0.15 - Initial Release`
5. Description: Copy from CHANGELOG.md
6. Click "Publish release"

This will trigger the GitHub Actions to build multi-architecture Docker images.

### 5. Set Up Pre-commit (Local Development)

For contributors:

```bash
# Install pre-commit
pip install pre-commit

# Install hooks
pre-commit install

# Run manually (optional)
pre-commit run --all-files
```

## User Installation

After publishing, users can install the add-on by:

1. Opening Home Assistant
2. Going to **Settings** → **Add-ons** → **Add-on Store**
3. Clicking the 3-dot menu (⋮) → **Repositories**
4. Adding: `https://github.com/elijahr/home-assistant-sshfs-mount`
5. Finding "SSHFS Mount" in the store
6. Installing the add-on

## Post-Publication

### Update README Badges

After first release, the badges in README.md will work:
- License badge: ✅ Works immediately
- Release badge: ✅ Works after creating first release

### Monitor Issues

- Watch for issues on GitHub
- Respond to user questions
- Track feature requests

### Future Releases

For future releases:

1. Update version in `config.yaml`
2. Update `CHANGELOG.md`
3. Commit changes
4. Create a new release on GitHub
5. GitHub Actions will automatically build new images

## GitHub Actions

Two workflows are configured:

1. **Builder** (.github/workflows/builder.yaml)
   - Builds multi-arch Docker images on push/PR/release
   - Publishes to GitHub Container Registry (ghcr.io)
   - Triggered on: push to main, PRs, releases

2. **Lint** (.github/workflows/lint.yaml)
   - Runs shellcheck, yamllint, markdownlint
   - Triggered on: push to main, PRs
   - Helps maintain code quality

## Notes

- The add-on is NOT published to HACS (Home Assistant Community Store)
- Users add the repository URL directly in Home Assistant
- Multi-architecture images are built automatically via GitHub Actions
- Docker images are hosted on GitHub Container Registry
