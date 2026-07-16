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

   `Data/PfbVersionMap.json` is currently populated as a **static, hand-curated file**
   (sourced via the Glean-assisted flow above, cross-checked against the FlashBlade
   Management REST API Reference table and per-version release-notes pages) rather than
   by this script. The automated generator above remains deferred until a non-token data
   path is wired up; when it lands, it should overwrite this file using the same
   `{ "<version>": { "purity": "<version>" } }` shape it already emits.

4. **`Build-PfbValueEnumMap.ps1`** — a separate, later phase (see "Value-enum extraction"
   below): loads the same cached specs and extracts prose-documented value enumerations
   (e.g. `Bucket.versioning`'s "Valid values are `none`, `enabled`, and `suspended`.")
   into `Data/PfbValueEnumMap.json`. Also runs entirely offline once specs are cached.

   ```powershell
   ./tools/Build-PfbValueEnumMap.ps1
   ```

## What's deliberately NOT in the capability map

The FlashBlade OpenAPI spec has no structural JSON Schema `enum` anywhere — verified
empty across every schema and parameter in both the oldest (fb2.10) and newest (fb2.27)
cached specs. Allowed values for fields like `Bucket.versioning` exist only as free-text
prose in `description` fields ("Valid values are `none`, `enabled`, and `suspended`."),
not as machine-readable constraints, so `Data/PfbCapabilityMap.json` (Phase 1's output)
tracks endpoint, parameter, and request-body top-level property *existence* only — not
their legal values. That prose *is* now extracted, but into a separate file by a separate
generator — see "Value-enum extraction" below — precisely because it's a different kind
of claim with a different reliability bar (see that section for why per-*value*
"introduced in version X" tracking specifically remains out of scope even there).

Also out of scope: hardware-model capability (//S vs //E — what the module's existing
~12 `-match`-based "not supported on this model" warnings actually gate on). That's a
separate axis from REST version, handled in a later phase from a different data source.

## Value-enum extraction (`Build-PfbValueEnumMap.ps1`)

A later, separate phase from the capability map above. `tools/lib/PfbValueEnumTools.ps1`
parses the "Valid/Possible values are/include ..." prose sentence out of a schema
property's or parameter's `description` — the only place these specs record a field's
legal value set, since (as above) there is no structural `enum` to read instead — and
`tools/Build-PfbValueEnumMap.ps1` diffs that across every cached spec version into
`Data/PfbValueEnumMap.json`:

```powershell
./tools/Build-PfbValueEnumMap.ps1
```

Key correctness rules (each has a dedicated regression test in
`Tests/PfbValueEnumTools.Tests.ps1`):
- Entries are keyed by **`(SchemaName, PropertyName)`**, never by bare property name.
  Two different schemas can share a property name with different legal values (e.g.
  `NfsExportPolicyRuleBase.access` is `root-squash`/`all-squash`/`no-squash`, while the
  presets-only `_presetWorkloadExportConfigurationNfsRule.access` is
  `root-squash`/`all-squash`/`no-root-squash`) — collapsing by bare name would silently
  merge them.
- Value extraction is scoped to the matched trigger *sentence* only, not the whole
  description, since some descriptions repeat the same backtick-quoted values again in
  explanatory prose that follows the enum sentence.
- A description that matches the trigger phrase but isn't actually a real enumeration
  (a numeric range, or free-text prose that happens to contain the words "valid values")
  is recorded as **unparsed**, not force-parsed and not silently dropped — surfaced in the
  manifest's `unparsedCount`/`unparsed` fields, same "never silently over-claim coverage"
  norm as the capability map's own coverage reporting.

The builder also writes `tools/PfbValueEnumReconciliation.md`, comparing every existing
hand-written cmdlet `ValidateSet` that encodes a spec-documented enum against this newly
extracted data (exact match / stale / not-found / collision with an unrelated same-named
field elsewhere in the spec). That report is informational only — it does not edit any
`Public/` cmdlet.

**`Data/PfbValueEnumMap.json`'s output is not consumed anywhere at runtime yet** — no
`ArgumentCompleter`, no `Assert-PfbApiCapability` enforcement. Whether/how to consume it
is a deliberate later decision once real coverage/accuracy numbers exist from this data,
same as how the capability map above sat idle until its own Phase 2 wired it in.

Per-enum-*value* "introduced in version X" tracking (e.g. knowing that `suspended` was
added to `Bucket.versioning` at some later REST version, as opposed to the field's own
overall `minVersion`) is intentionally not attempted — the design doc's exploration found
no reliable way to diff individual values across versions given how often the same prose
gets reworded without the value set itself changing. The manifest tracks each field's
current legal value set and the field's own earliest-seen version only.

## Tests

`Tests/PfbSpecTools.Tests.ps1`, `Tests/PfbVersionMapTools.Tests.ps1`, and
`Tests/Build-PfbCapabilityMap.Tests.ps1` cover the capability-map extraction/diffing logic
against small synthetic fixtures — no network access required. One additional test in
`Build-PfbCapabilityMap.Tests.ps1` checks the real committed manifest for coverage gaps
against the newest locally-cached spec, and skips gracefully if `tools/specs/` (gitignored
— run `Update-PfbApiSpecs.ps1` first) or `Data/PfbCapabilityMap.json` aren't present.

`Tests/PfbValueEnumTools.Tests.ps1` and `Tests/Build-PfbValueEnumMap.Tests.ps1` cover the
value-enum extraction/diffing logic the same way, plus a `Bucket.versioning` regression
fixture and a squash-mode-gotcha fixture (see "Value-enum extraction" above). Their real-
manifest checks skip gracefully if `tools/specs/` or `Data/PfbValueEnumMap.json` aren't
present.

## CI

`.github/workflows/update-api-capability-map.yml` runs this pipeline weekly (and on
manual dispatch): re-fetches the full spec history into an ephemeral (non-committed)
cache, rebuilds `Data/PfbCapabilityMap.json`, and opens a PR if it changed — i.e. the
swagger index published a new REST version, or an existing endpoint gained new
parameters/fields. Requires the repository's Actions settings to permit workflow-created
pull requests. The `EVERPURE_SUPPORT_TOKEN` secret is optional — when absent, the
version-map step is skipped and only the capability map updates.

`Build-PfbValueEnumMap.ps1` is **not yet wired into this (or any) CI workflow** — run it
manually against a local `tools/specs/` cache for now. Folding it into the weekly job is a
natural follow-on once its output has a runtime consumer worth keeping fresh on a
schedule.
