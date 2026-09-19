---
name: systematic-debugging
description: Systematic debugging workflow reproduce-hypothesis-test-fix-verify. Use when debugging errors, failures, or unexpected behavior.
---

# Systematic Debugging

Reproduce → hypothesize → test one at a time → fix → verify.

1. **Reproduce**: trigger the error, capture the FULL log/output. No log, no debug.
2. **Hypothesis**: form ONE hypothesis about the root cause, based on code read via `read` (never from memory).
3. **Test**: design the smallest check that proves/disproves it. Record the result.
4. **Fix**: only after a hypothesis is confirmed. Edit minimally.
5. **Verify**: run the relevant test/lint/build. Report command + result.
6. **Stop rule**: 3 failed attempts with the same approach → stop, report what was tried, change approach or ask the user.
