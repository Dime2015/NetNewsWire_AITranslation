# Phase 3 persistent evidence

`manifest.json` is the machine-readable entry point for the account-qualified Feed→Article slice. This directory is the repository-persistent evidence gate; the `/private/tmp/babel2-phase3-*` paths recorded in the JSON files are original temporary sources only.

The package deliberately keeps only:

- targeted and full `xcresulttool` summary exports;
- package/build/test result metadata and SHA-256 digests;
- a privacy-safe runtime probe and structural live-trace summary;
- the final Release r1 Simulator screenshot;
- SecretKey and six-environment-variable status, never secret values.

No raw logs, complete xcresult bundles, DerivedData, tokens, URLs, article bodies, account credentials, or empty install/terminate logs are copied here. The screenshot is a root-state proof only. Runtime Feeds→single source→Article interaction remains `INTERACTION_BLOCKED`; Phase 1A, old resource allowlist, physical iPhone, and later product work remain open.
