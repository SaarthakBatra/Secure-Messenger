# MultiLingo Dual-Repo Sync & Maintenance Guide

This guide defines the workflow for managing the dual-repo architecture of the MultiLingo project, enabling private, full-context development while presenting a clean, resume-ready version publicly.

## Repository Setup

1. **Private Repository (`dev` remote)**: Contains all developer tools, credentials templates, maintenance logs, and configuration directories (`.agent/`, `.antigravity/`). This is the repository you connect to **Render** for deployments.
2. **Public Repository (`origin` remote)**: Contains sanitized code showcasing front-end UI, system architecture, and general capabilities, completely stripped of stealth elements or maintenance metadata.

---

## The "Clean Sync" Workflows

### Scenario A: Initializing the Public Repository (First-Time Release)
If you have a messy local history and want to initialize a clean, single-commit history on your public `main` branch:

```bash
# 1. Ensure you are on dev and all changes are committed
git checkout dev
git commit -am "Save development state"

# 2. Create a temporary orphan branch containing current state with no history
git checkout --orphan temp-main

# 3. Clean files (files ignored by main's .gitignore will remain untracked)
# Delete metadata folders manually or via git rm
git rm -rf --cached .agent/ .antigravity/ temp/

# 4. Commit the clean state
git add -A
git commit -m "Initial Public Release: MultiLingo Core"

# 5. Push this clean state to the public main branch
git push origin temp-main:main --force

# 6. Delete the temporary branch locally and return to dev
git checkout dev
git branch -D temp-main
```

### Scenario B: Ongoing Sync (Strip-on-Merge)
When you have completed features on the private `dev` branch and want to push the updates to the public `main` branch without leaking metadata:

```bash
# 1. Switch to the main branch
git checkout main

# 2. Merge dev changes without committing immediately (allows review and staging)
git merge dev --no-commit --no-ff

# 3. Force-remove metadata directories from the staging area to ensure they aren't merged
git rm -r --cached .agent/ .antigravity/ MAINTENANCE.md 2>/dev/null || true

# 4. Commit the sanitized merge
git commit -m "Sync: Integrate updates from development"

# 5. Push the clean commit to the public remote
git push origin main

# 6. Switch back to your private development branch
git checkout dev
```
