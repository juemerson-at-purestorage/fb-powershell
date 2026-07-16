<#
.SYNOPSIS
    Shared helpers for extracting prose-documented value enumerations (e.g.
    Bucket.versioning's "Valid values are `none`, `enabled`, and `suspended`.") from
    FlashBlade OpenAPI specs. Dot-sourced by tools/Build-PfbValueEnumMap.ps1 and its
    Pester tests, parallel to tools/lib/PfbSpecTools.ps1.

.DESCRIPTION
    As tools/lib/PfbSpecTools.ps1's header documents, the FlashBlade OpenAPI spec has
    NO structural JSON Schema "enum" anywhere. Allowed values for fields like
    Bucket.versioning are documented only in free-text `description` prose. This file
    parses that prose instead.

    Two correctness rules discovered while building this against the real cached specs
    (fb2.27.json), each with its own regression test — do not regress either:

    1. MANY schemas (e.g. Bucket, NfsExportPolicyRuleBase) are `allOf` compositions with
       no direct `.properties` of their own — the real property and its `description`
       live behind `allOf` branches and $ref's. Reading `.description` directly off such
       a schema's own property node returns nothing; the walker below resolves $ref and
       recurses into `allOf`, exactly like Get-PfbSchemaPropertyNames in PfbSpecTools.ps1.

    2. Value extraction must be scoped to the matched "Valid/Possible values (are|include)
       ... ." TRIGGER SENTENCE only, not the whole description. Several descriptions
       repeat the enum's own backtick-quoted values again in explanatory prose *after*
       the trigger sentence (e.g. `_presetWorkloadExportConfigurationNfsRule.access`
       explains each value in a following paragraph) - extracting from the whole
       description would over-collect from that trailing prose, not just the enum
       itself. It happens not to change the *value set* for that particular field (the
       trailing prose repeats the same values), but it is not safe to rely on that in
       general, so the sentence must be isolated first.

    Two trigger phrasings were confirmed live against fb2.27.json: "Valid values
    are/include ..." (dominant, ~376 hits) and "Possible values are/include ..." (a
    real, non-one-off variant, ~25 hits, e.g. AlertWatcher(Post).minimum_notification_severity).
    Both are treated identically once the trigger sentence is isolated.

    Correctness rule carried over from the design doc, confirmed live: key every record
    by (SchemaName, PropertyName) or (ParameterComponentName), never by bare property
    name alone. NfsExportPolicyRuleBase.access ('root-squash'/'all-squash'/'no-squash')
    and the presets-only _presetWorkloadExportConfigurationNfsRule.access
    ('root-squash'/'all-squash'/'no-root-squash') are two distinct schemas that happen
    to share a property name with non-identical value spellings - collapsing by bare
    name would silently merge them into one incoherent value list.
#>

# Deliberately NOT Set-StrictMode — same reasoning as PfbSpecTools.ps1: these functions
# walk heterogeneous PSCustomObjects from JSON where a given node legitimately may or
# may not have a given property (not every schema has .properties or .allOf).

# Trigger sentence: "Valid values are `a`, `b`." or "Possible values include ...".
# Captures the sentence itself so downstream parsing only ever looks inside it.
$script:PfbValueEnumTriggerPattern = '(?:Valid|Possible) values (?:are|include)[^.]*\.'

function Get-PfbValueEnumTriggerSentence {
    <#
    .SYNOPSIS
        Returns the "Valid/Possible values ... ." sentence from a description, or $null
        if the description does not contain one.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Description
    )

    if (-not $Description) { return $null }

    $m = [regex]::Match($Description, $script:PfbValueEnumTriggerPattern)
    if (-not $m.Success) { return $null }

    return $m.Value
}

function ConvertFrom-PfbValueEnumProse {
    <#
    .SYNOPSIS
        Parses a single trigger sentence (see Get-PfbValueEnumTriggerSentence) into its
        enumerated values, if it is actually an enumeration.
    .DESCRIPTION
        Tries, in order: backtick-quoted values (the dominant pattern), then
        double-quoted values, then bare comma-separated tokens — only for a trigger
        sentence that didn't already parse via an earlier pattern. Sentences that match
        the trigger phrase but are not really an enumeration (e.g. a numeric range, or
        free-text prose that happens to contain the trigger words) are explicitly
        classified as unparsed rather than force-parsed, per this repo's "never silently
        over-claim coverage" convention (see Assert-PfbApiCapability / PfbSpecTools.ps1).
    .OUTPUTS
        [PSCustomObject]@{ Values = string[]; Parsed = bool; TriggerText = string }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TriggerSentence
    )

    # Backtick-quoted: `none`, `enabled`, and `suspended`.
    $backtickMatches = [regex]::Matches($TriggerSentence, '`([^`]+)`')
    if ($backtickMatches.Count -gt 0) {
        $values = $backtickMatches | ForEach-Object { $_.Groups[1].Value }
        return [PSCustomObject]@{ Values = @($values); Parsed = $true; TriggerText = $TriggerSentence }
    }

    # Double-quoted: "policy", "sacl".
    $quoteMatches = [regex]::Matches($TriggerSentence, '"([^"]+)"')
    if ($quoteMatches.Count -gt 0) {
        $values = $quoteMatches | ForEach-Object { $_.Groups[1].Value }
        return [PSCustomObject]@{ Values = @($values); Parsed = $true; TriggerText = $TriggerSentence }
    }

    # Bare comma-separated tokens after "are"/"include", e.g.:
    #   "Valid values include QSFP, QSFP+, QSFP28, QSFP56, QSFP-DD, RJ-45, and -."
    # Deliberately conservative: only fires when the sentence has no quote characters at
    # all (so it can't misfire on the malformed-quote case, e.g. "include 'success' or
    # failure'." — a real, confirmed-malformed example in the source spec that is left
    # unparsed rather than force-parsed) and the tail actually looks like a short
    # comma/space-separated token list (no long runs of lowercase prose words).
    if ($TriggerSentence -notmatch '[''"]') {
        # [\s\S] (not '.') so the lazy capture can span an embedded newline — real spec
        # prose wraps mid-sentence (e.g. "...`all-squash`, and\n`no-root-squash`.") and
        # '.' does not match '\n' by default, which would otherwise force the match to
        # anchor past the embedded newline onto a later, spurious "are"/"include".
        $tail = [regex]::Match($TriggerSentence, '(?:are|include)\s+([\s\S]+?)\.\s*$')
        if ($tail.Success) {
            $rawTokens = $tail.Groups[1].Value -replace '\band\b', ',' -split ','
            $tokens = $rawTokens | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            # Reject if any token contains whitespace (a real value token here, e.g.
            # "QSFP28" or "-", never does) — that indicates free-text prose rather than
            # a token list, e.g. "controllers and blades from hardware list".
            $looksLikeTokenList = $tokens.Count -gt 0 -and -not ($tokens | Where-Object { $_ -match '\s' })
            if ($looksLikeTokenList) {
                return [PSCustomObject]@{ Values = @($tokens); Parsed = $true; TriggerText = $TriggerSentence }
            }
        }
    }

    return [PSCustomObject]@{ Values = @(); Parsed = $false; TriggerText = $TriggerSentence }
}

function Get-PfbSchemaPropertyDescriptions {
    <#
    .SYNOPSIS
        Returns resolved { propertyName -> description } pairs for a (possibly $ref'd /
        allOf'd) schema — the description-carrying counterpart to
        Get-PfbSchemaPropertyNames in PfbSpecTools.ps1.
    .DESCRIPTION
        Resolves $ref chains and merges across "allOf" branches, same pattern as
        Get-PfbSchemaPropertyNames. Also descends into array `items` schemas so a
        property typed as an array-of-enum-strings is still captured. Does not attempt
        oneOf/anyOf (not used for FlashBlade schemas as of the versions surveyed).
        A property whose first-seen branch supplies a description wins; later branches
        supplying the same property name do not overwrite it (first-branch-wins, same
        precedence as Get-PfbSchemaPropertyNames's de-dup).
    .OUTPUTS
        Hashtable of propertyName -> description string (only properties with a
        non-empty resolved description are included).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Schema,

        [Parameter(Mandatory)]
        $Spec,

        [int]$MaxDepth = 8
    )

    $result = @{}
    if ($null -eq $Schema -or $MaxDepth -le 0) { return $result }

    $resolved = Resolve-PfbRef -Node $Schema -Spec $Spec
    if ($null -eq $resolved) { return $result }

    if ($resolved.PSObject.Properties.Name -contains 'properties' -and $resolved.properties) {
        foreach ($propName in $resolved.properties.PSObject.Properties.Name) {
            $propSchema = Resolve-PfbRef -Node $resolved.properties.$propName -Spec $Spec
            if (-not $propSchema) { continue }

            $desc = $null
            if ($propSchema.PSObject.Properties.Name -contains 'description' -and $propSchema.description) {
                $desc = $propSchema.description
            }
            elseif ($propSchema.PSObject.Properties.Name -contains 'items' -and $propSchema.items) {
                $itemSchema = Resolve-PfbRef -Node $propSchema.items -Spec $Spec
                if ($itemSchema -and $itemSchema.PSObject.Properties.Name -contains 'description' -and $itemSchema.description) {
                    $desc = $itemSchema.description
                }
            }

            if ($desc -and -not $result.ContainsKey($propName)) {
                $result[$propName] = $desc
            }
        }
    }

    if ($resolved.PSObject.Properties.Name -contains 'allOf' -and $resolved.allOf) {
        foreach ($branch in $resolved.allOf) {
            $branchResult = Get-PfbSchemaPropertyDescriptions -Schema $branch -Spec $Spec -MaxDepth ($MaxDepth - 1)
            foreach ($k in $branchResult.Keys) {
                if (-not $result.ContainsKey($k)) { $result[$k] = $branchResult[$k] }
            }
        }
    }

    return $result
}

function Get-PfbSpecValueEnums {
    <#
    .SYNOPSIS
        Extracts every prose-documented value enumeration from a single FlashBlade
        OpenAPI spec, across both components.schemas properties and
        components.parameters.
    .DESCRIPTION
        Never collapses by bare property/parameter name — each record's Key is
        "<SchemaName>.<PropertyName>" for schema properties (Kind = 'schema') or the
        parameter's own component name (Kind = 'parameter'). Two schemas sharing a
        property name with different value sets (e.g. the squash-mode case) always
        produce two separate records.

        Every description that matches the trigger phrase produces a record, whether or
        not it successfully parsed into values — callers must check .Parsed rather than
        assume every returned record has a usable value list. This is deliberate: it is
        the mechanism by which "unparsed" prose is surfaced rather than silently dropped.
    .OUTPUTS
        [PSCustomObject]@{ Key; Kind; Name; Values; Parsed; TriggerText }

        Key is the collision-safe identity ("SchemaName.PropertyName", or the parameter's
        own components.parameters dictionary key) — always unique, always what downstream
        diffing/storage should key on. Name is the field's own short name as it actually
        appears on the wire (the schema property name, or the parameter's "name" field,
        e.g. "protocol") — the more useful match target for reconciling against a
        cmdlet's hand-written parameter, since a query parameter's components.parameters
        dictionary key does not have to equal its wire "name".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Spec
    )

    $results = [System.Collections.Generic.List[object]]::new()

    if ($Spec.components -and $Spec.components.schemas) {
        foreach ($schemaName in $Spec.components.schemas.PSObject.Properties.Name) {
            $descriptions = Get-PfbSchemaPropertyDescriptions -Schema $Spec.components.schemas.$schemaName -Spec $Spec

            foreach ($propName in $descriptions.Keys) {
                $trigger = Get-PfbValueEnumTriggerSentence -Description $descriptions[$propName]
                if (-not $trigger) { continue }

                $parsed = ConvertFrom-PfbValueEnumProse -TriggerSentence $trigger
                $results.Add([PSCustomObject]@{
                    Key         = "$schemaName.$propName"
                    Kind        = 'schema'
                    Name        = $propName
                    Values      = $parsed.Values
                    Parsed      = $parsed.Parsed
                    TriggerText = $parsed.TriggerText
                })
            }
        }
    }

    if ($Spec.components -and $Spec.components.parameters) {
        foreach ($paramName in $Spec.components.parameters.PSObject.Properties.Name) {
            $paramNode = $Spec.components.parameters.$paramName
            if ($paramNode.PSObject.Properties.Name -notcontains 'description') { continue }

            $trigger = Get-PfbValueEnumTriggerSentence -Description $paramNode.description
            if (-not $trigger) { continue }

            $wireName = if ($paramNode.PSObject.Properties.Name -contains 'name' -and $paramNode.name) { $paramNode.name } else { $paramName }

            $parsed = ConvertFrom-PfbValueEnumProse -TriggerSentence $trigger
            $results.Add([PSCustomObject]@{
                Key         = $paramName
                Kind        = 'parameter'
                Name        = $wireName
                Values      = $parsed.Values
                Parsed      = $parsed.Parsed
                TriggerText = $parsed.TriggerText
            })
        }
    }

    return $results
}
