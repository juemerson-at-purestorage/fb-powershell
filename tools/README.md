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
   Purity//FB-version pairing, from a single SSOT (Single Source of Truth) API call: a
   scoped proxy in front of Fluid Topics (owner: ***REMOVED***), delta-synced nightly, that
   returns the full REST<->Purity//FB mapping table for every version in one HTML
   response. Requires an API key (`$env:SSOT_API_KEY`, sent as an `x-api-key` header);
   without one, this script just reports which versions need lookup and exits without
   failing.

   ```powershell
   $env:SSOT_API_KEY = '...'
   ./tools/Update-PfbVersionMap.ps1
   ```

4. **`Build-PfbValueEnumMap.ps1`** — a separate, later phase (see "Value-enum extraction"
   below): loads the same cached specs and extracts prose-documented value enumerations
   (e.g. `Bucket.versioning`'s "Valid values are `none`, `enabled`, and `suspended`.")
   into `Reports/PfbValueEnumMap.json`. Also runs entirely offline once specs are cached.

   ```powershell
   ./tools/Build-PfbValueEnumMap.ps1
   ```

5. **`Build-PfbApiDriftReport.ps1`** — the newest phase (see `Reports/README.md`): composes
   the capability map, cmdlet inventory, and value-enum data above into one combined
   "what's changed that we haven't caught up to" report, covering uncovered endpoints, new
   parameters on endpoints we already call, drift on existing `ValidateSet`s, and new
   `ValidateSet` candidates (reusing `Build-PfbFieldCmdletMap.ps1`'s `matched` output
   directly). See `tools/lib/PfbApiDriftTools.ps1` for the underlying functions.

   ```powershell
   ./tools/Build-PfbApiDriftReport.ps1
   ```

   Pass `-SinceVersion` to isolate what a single new REST release actually added instead
   of the full accumulated backlog -- e.g. after 2.27 ships, `-SinceVersion '2.26'` filters
   `uncoveredEndpoints`/`parameterGaps` down to just the items introduced by 2.27. Only
   those two categories support it: `validateSetDrift`/`newValidateSetCandidates` don't
   carry a per-value introduced-version in the capability map to filter on.

   ```powershell
   ./tools/Build-PfbApiDriftReport.ps1 -SinceVersion '2.26'
   ```

   `parameterGaps` also never reports a small set of non-actionable fields
   (`$script:PfbNonActionableParameters` in `tools/lib/PfbApiDriftTools.ps1`:
   `X-Request-ID`, `continuation_token`, `offset`) -- these are declared on nearly every
   endpoint and would otherwise drown out real gaps.

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
`Reports/PfbValueEnumMap.json`:

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
- The extractor also covers a parameter defined **inline** directly on a
  `spec.paths.<path>.<method>` operation — not just `components.schemas` properties and
  named `components.parameters` entries. This matters because a field can be inline for
  years before a later spec refactor turns it into a `$ref`: `GET /arrays/space`'s `type`
  query parameter was inline (full "Valid values are `array`, `file-system`,
  `object-store`." description) from REST 2.0 through 2.16, only becoming
  `$ref: '#/components/parameters/Type'` at 2.17 — a pure documentation refactor, not an
  API change. Without this pass, the field's true `minVersion` (2.0) would be invisible
  and its earlier, inline-only history would be lost entirely. Keyed by
  `"<METHOD> <path>#<paramName>"` (`Kind = 'inline-parameter'`), never the bare parameter
  name, for the same never-collapse reason as above.
- Value extraction is scoped to the matched trigger *sentence* only, not the whole
  description, since some descriptions repeat the same backtick-quoted values again in
  explanatory prose that follows the enum sentence.
- A description that matches the trigger phrase but isn't actually a real enumeration
  (a numeric range, or free-text prose that happens to contain the words "valid values")
  is recorded as **unparsed**, not force-parsed and not silently dropped — surfaced in the
  manifest's `unparsedCount`/`unparsed` fields, same "never silently over-claim coverage"
  norm as the capability map's own coverage reporting.

The builder also writes `Reports/PfbValueEnumReconciliation.md`, comparing every existing
hand-written cmdlet `ValidateSet` that encodes a spec-documented enum against this newly
extracted data (exact match / stale / not-found / collision with an unrelated same-named
field elsewhere in the spec). That report is informational only — it does not edit any
`Public/` cmdlet.

**`Reports/PfbValueEnumMap.json`'s output is not consumed anywhere at runtime yet** — no
`ArgumentCompleter`, no `Assert-PfbApiCapability` enforcement. Whether/how to consume it
is a deliberate later decision once real coverage/accuracy numbers exist from this data,
same as how the capability map above sat idle until its own Phase 2 wired it in.

Per-enum-*value* "introduced in version X" tracking (e.g. knowing that `suspended` was
added to `Bucket.versioning` at some later REST version, as opposed to the field's own
overall `minVersion`) is intentionally not attempted — the design doc's exploration found
no reliable way to diff individual values across versions given how often the same prose
gets reworded without the value set itself changing. The manifest tracks each field's
current legal value set and the field's own earliest-seen version only.

## Field-to-cmdlet mapping (`Build-PfbFieldCmdletMap.ps1`)

Joins the cmdlet parameter inventory (from `PfbCmdletParamTools.ps1`, which reads `Public/`
cmdlet ASTs) against the prose value-enum data extracted above to recommend, per typed
`Public/` parameter that lacks a `ValidateSet` today, whether it should become a
`ValidateSet` or an `ArgumentCompleter`:

```powershell
./tools/Build-PfbFieldCmdletMap.ps1
```

Key correctness rules:
- A parameter is recommended `ValidateSet` only if: the parameter's wire field appears in
  the spec, it has a documented value enumeration, that enumeration is present unchanged in
  every REST version from the field's introduction onward, and the field was present since
  the oldest cached version.
- A parameter is recommended `ArgumentCompleter` if the field exists but the value set
  changed at any point in the history, or the field was introduced in a newer version.
- A parameter is classified `collision` if its wire name matches multiple schema keys with
  different value sets, or `not-found-in-resource` if the wire name exists in the spec but
  not under any schema the cmdlet's resource hint suggests. Both require manual follow-up
  to ensure the intent is captured.
- An **`inline-parameter`**-kind value-enum record (see "Value-enum extraction" above) is
  keyed by exact endpoint identity (`"<METHOD> <path>#<paramName>"`), so when
  `PfbCmdletParamTools.ps1`'s AST inventory can determine exactly which endpoint a given
  cmdlet parameter calls, an exact match there overrides an otherwise-ambiguous
  `parameter`-kind wire name — this is precisely how `Get-PfbArraySpace -Type` resolves to
  `matched`/`ValidateSet` instead of `collision`, even though its wire name `type` also
  matches two disagreeing `components.parameters` definitions (`Type` and
  `Type_for_performance`) elsewhere in the spec.
- `attributesOnly` and `typedUnresolved` entries are *reported*, not resolved — they list
  parameters that either have no typed field to attach validation to (attributes-only),
  or have a wire name that couldn't be resolved to a spec key. These require human
  decisions (add a new typed parameter, or leave as-is); the script does not edit any
  `Public/` cmdlet.

The builder also writes `Reports/PfbFieldCmdletMapping.md`, a Markdown table summarizing
every candidate and its recommendation — informational only, not consumed at runtime.

**`Reports/PfbFieldCmdletMap.json`'s output is not consumed anywhere at runtime yet** — no
`ValidateSet` or `ArgumentCompleter` is added to any `Public/` cmdlet by this script.
Whether/how to consume it is a deliberate follow-on decision.

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
manifest checks skip gracefully if `tools/specs/` or `Reports/PfbValueEnumMap.json` aren't
present.

## CI

`.github/workflows/update-api-capability-map.yml` runs this pipeline weekly (and on
manual dispatch): re-fetches the full spec history into an ephemeral (non-committed)
cache, rebuilds `Data/PfbCapabilityMap.json`, and opens a PR if it changed — i.e. the
swagger index published a new REST version, or an existing endpoint gained new
parameters/fields. Requires the repository's Actions settings to permit workflow-created
pull requests. The `EVERPURE_SUPPORT_TOKEN` secret is optional — when absent, the
version-map step is skipped and only the capability map updates.

`Build-PfbValueEnumMap.ps1`, `Build-PfbFieldCmdletMap.ps1`, and `Build-PfbApiDriftReport.ps1`
all run as part of the same weekly/dispatch job, right after the capability map is rebuilt,
so `Reports/PfbValueEnumMap.json`, `Reports/PfbFieldCmdletMap.json`, and
`Reports/PfbApiDriftReport.json` (+ their Markdown companions) stay fresh alongside
`Data/PfbCapabilityMap.json`.
