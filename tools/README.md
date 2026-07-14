# API Capability Map Toolchain

Generates `Data/PfbCapabilityMap.json` — a manifest mapping every FlashBlade REST API
endpoint (and its parameters and request-body fields) to the REST version it was
introduced in. This is Phase 1 of the version-awareness effort described in the Phase 1
design doc; it produces the data that later phases (a per-cmdlet capability check, and
version-aware tab-completion) will consume. It does not itself add any runtime behavior
to the module.

## Scripts

Run in this order:

1. **`Update-PfbApiSpecs.ps1`** — fetches every published REST version's OpenAPI spec
   from `https://code.purestorage.com/swagger/` and caches it as pretty-printed JSON
   under `tools/specs/fb<version>.json`. Skips versions already cached unless `-Force`.
   The spec isn't a plain downloadable file — see `lib/PfbSpecTools.ps1` for why, and how
   it's extracted from the ReDoc reference page.

   `tools/specs/` is **gitignored, not committed**. It's a build-time input only — never
   read at runtime — and at ~1-3MB per REST version (~48MB across the full history as of
   2026-07), committing it would bloat every clone of this repo. That matters here more
   than in a typical repo: today, cloning this repo and copying the checkout straight into
   `$env:PSModulePath` *is* the documented "from source" install method (see the root
   README), so anything committed at repo root ships to every user, not just contributors.
   Locally, just run the fetcher once and the cache persists on disk for reuse; CI
   re-fetches the full set fresh on every run (a few minutes, and it only runs weekly).

   ```powershell
   ./tools/Update-PfbApiSpecs.ps1                       # fetch anything new
   ./tools/Update-PfbApiSpecs.ps1 -Versions 2.26,2.27 -Force   # re-fetch specific versions
   ```

2. **`Build-PfbCapabilityMap.ps1`** — loads all cached specs in ascending version order
   and diffs them into `Data/PfbCapabilityMap.json`. Runs entirely offline once specs are
   cached.

   ```powershell
   ./tools/Build-PfbCapabilityMap.ps1
   ```

3. **`Update-PfbVersionMap.ps1`** — builds `Data/PfbVersionMap.json`, the REST-version to
   Purity//FB-version pairing, from the per-version release notes on the Everpure support
   site. **Currently a skeleton**: the release-notes pages require a service-key token
   (`$env:EVERPURE_SUPPORT_TOKEN`) that isn't wired up yet, so without one this script
   just reports which versions need lookup and exits without failing. See the script's
   header comment for the Glean-assisted manual fallback.

## What's deliberately NOT in the manifest

The FlashBlade OpenAPI spec has no structural JSON Schema `enum` anywhere — verified
empty across every schema and parameter in both the oldest (fb2.10) and newest (fb2.27)
cached specs. Allowed values for fields like `Bucket.versioning` exist only as free-text
prose in `description` fields ("Valid values are `none`, `enabled`, and `suspended`."),
not as machine-readable constraints. Per-enum-value "introduced in version X" tracking is
therefore not derivable from this data source and is out of scope here. The manifest
tracks endpoint, parameter, and request-body top-level property existence only.

Also out of scope: hardware-model capability (//S vs //E — what the module's existing
~12 `-match`-based "not supported on this model" warnings actually gate on). That's a
separate axis from REST version, handled in a later phase from a different data source.

## Tests

`Tests/PfbSpecTools.Tests.ps1`, `Tests/PfbVersionMapTools.Tests.ps1`, and
`Tests/Build-PfbCapabilityMap.Tests.ps1` cover the extraction/diffing logic against small
synthetic fixtures — no network access required. One additional test in
`Build-PfbCapabilityMap.Tests.ps1` checks the real committed manifest for coverage gaps
against the newest locally-cached spec, and skips gracefully if `tools/specs/` (gitignored
— run `Update-PfbApiSpecs.ps1` first) or `Data/PfbCapabilityMap.json` aren't present.

## CI

`.github/workflows/update-api-capability-map.yml` runs this pipeline weekly (and on
manual dispatch): re-fetches the full spec history into an ephemeral (non-committed)
cache, rebuilds `Data/PfbCapabilityMap.json`, and opens a PR if it changed — i.e. the
swagger index published a new REST version, or an existing endpoint gained new
parameters/fields. Requires the repository's Actions settings to permit workflow-created
pull requests. The `EVERPURE_SUPPORT_TOKEN` secret is optional — when absent, the
version-map step is skipped and only the capability map updates.
