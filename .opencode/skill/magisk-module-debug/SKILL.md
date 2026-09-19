---
name: magisk-module-debug
description: Debug Magisk modules via logcat/dmesg and module structure checks. Use when fixing Magisk modules, boot scripts, service.sh or post-fs-data.sh.
---

# Magisk Module Debug

1. **Structure**: verify `module.prop` exists with valid `id`/`versionCode`; check `service.sh`, `post-fs-data.sh` are executable shell scripts (`bash -n` + `shellcheck`).
2. **Logs**: `logcat -d | grep -i magisk` for Magisk/denied errors; `dmesg | tail` for kernel-level failures.
3. **Isolate**: disable other modules, test one at a time. Check SELinux denials in logcat.
4. **Fix minimally**, reboot-test if needed, and record symptom → root cause → fix in NOTES.md.
