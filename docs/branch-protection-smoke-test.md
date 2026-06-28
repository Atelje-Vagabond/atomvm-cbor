# Branch Protection Smoke Test

This temporary document is used to verify pull request checks, required status checks, and CODEOWNERS review behavior.

Expected behavior:

- PR Check runs.
- Security Scan runs.
- Gitleaks scan runs.
- Workflow-specific scans do not run for a docs-only change.
- Shell script lint does not run for a docs-only change.
- Code owner review is required before merge.

This file is temporary and should not be merged.
