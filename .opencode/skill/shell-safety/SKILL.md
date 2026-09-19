---
name: shell-safety
description: Shell script safety checks with bash -n and shellcheck for Termux/Android. Use when writing or running shell scripts.
---

# Shell Safety (Termux/Android)

1. Before executing any new/edited script: `bash -n <file>` (syntax) and `shellcheck <file>` (lint). Fix all errors, review warnings.
2. Check command availability first: `command -v <nama>`. Never assume GNU tools exist in Termux.
3. No destructive command (`rm -rf`, `dd`, `mkfs`, format) without explicit user confirmation.
4. Quote paths with spaces. Prefer dedicated file tools over `sed`/`awk` pipelines for edits.
5. Report: what was checked, what failed, what was fixed.
