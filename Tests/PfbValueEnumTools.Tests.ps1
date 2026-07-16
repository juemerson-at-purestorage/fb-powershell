#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Unit tests for tools/lib/PfbValueEnumTools.ps1 — the prose "Valid/Possible values"
    extraction helpers used by tools/Build-PfbValueEnumMap.ps1.
.DESCRIPTION
    Pure-function unit tests against small synthetic spec objects (same
    [PSCustomObject]-fixture style as Tests/PfbSpecTools.Tests.ps1) — no network access
    and no dependency on the real cached specs in tools/specs/.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'tools/lib/PfbSpecTools.ps1')
    . (Join-Path $repoRoot 'tools/lib/PfbValueEnumTools.ps1')
}

Describe 'Get-PfbValueEnumTriggerSentence' {
    It 'extracts a "Valid values are ... ." sentence' {
        $desc = "The versioning state for objects within the bucket. Valid values are ``none``, ``enabled``, and ``suspended``."
        $trigger = Get-PfbValueEnumTriggerSentence -Description $desc
        $trigger | Should -Be 'Valid values are `none`, `enabled`, and `suspended`.'
    }

    It 'extracts a "Possible values include ... ." sentence' {
        $desc = "The minimum severity for notifications. Possible values include ``info``, ``warning``, and ``critical``. Defaults to info."
        $trigger = Get-PfbValueEnumTriggerSentence -Description $desc
        $trigger | Should -Be 'Possible values include `info`, `warning`, and `critical`.'
    }

    It 'returns $null when no trigger phrase is present' {
        Get-PfbValueEnumTriggerSentence -Description 'A perfectly ordinary free-text description.' | Should -BeNullOrEmpty
    }

    It 'returns $null for an empty or missing description' {
        Get-PfbValueEnumTriggerSentence -Description $null | Should -BeNullOrEmpty
        Get-PfbValueEnumTriggerSentence -Description '' | Should -BeNullOrEmpty
    }

    It 'isolates only the trigger sentence, not trailing prose that repeats the values' {
        # Regression for the trigger-sentence-scoping rule: the preset export-rule
        # description explains each backtick-quoted value again in a paragraph *after*
        # the enum sentence — the trigger sentence itself must not swallow that tail.
        $desc = @'
Specifies access control for the export. Valid values are `root-squash`, `all-squash`, and
`no-root-squash`.
`root-squash` prevents client users and groups with root privilege from mapping their
root privilege to a file system.
'@
        $trigger = Get-PfbValueEnumTriggerSentence -Description $desc
        $trigger | Should -Match '^Valid values are `root-squash`, `all-squash`, and\s*\n`no-root-squash`\.$'
        $trigger | Should -Not -Match 'prevents client users'
    }
}

Describe 'ConvertFrom-PfbValueEnumProse' {
    It 'parses the dominant backtick-quoted pattern' {
        $result = ConvertFrom-PfbValueEnumProse -TriggerSentence 'Valid values are `none`, `enabled`, and `suspended`.'
        $result.Parsed | Should -BeTrue
        $result.Values | Should -Be @('none', 'enabled', 'suspended')
    }

    It 'parses a double-quoted value list' {
        $result = ConvertFrom-PfbValueEnumProse -TriggerSentence 'Valid values are "policy", "sacl".'
        $result.Parsed | Should -BeTrue
        $result.Values | Should -Be @('policy', 'sacl')
    }

    It 'parses a bare comma-separated token list' {
        $result = ConvertFrom-PfbValueEnumProse -TriggerSentence 'Valid values include QSFP, QSFP+, QSFP28, QSFP56, QSFP-DD, RJ-45, and -.'
        $result.Parsed | Should -BeTrue
        $result.Values | Should -Be @('QSFP', 'QSFP+', 'QSFP28', 'QSFP56', 'QSFP-DD', 'RJ-45', '-')
    }

    It 'does not force-parse a malformed/unbalanced-quote sentence' {
        $result = ConvertFrom-PfbValueEnumProse -TriggerSentence "Valid values include 'success' or failure'."
        $result.Parsed | Should -BeFalse
        $result.Values | Should -BeNullOrEmpty
        $result.TriggerText | Should -Not -BeNullOrEmpty
    }

    It 'does not force-parse a numeric-range sentence that happens to match the trigger phrase' {
        $result = ConvertFrom-PfbValueEnumProse -TriggerSentence "Valid values are`nin the range of 300000 and 10800000."
        $result.Parsed | Should -BeFalse
        $result.Values | Should -BeNullOrEmpty
    }

    It 'does not force-parse free-text prose that happens to match the trigger phrase' {
        $result = ConvertFrom-PfbValueEnumProse -TriggerSentence "Valid values are controllers`nand blades from hardware list."
        $result.Parsed | Should -BeFalse
        $result.Values | Should -BeNullOrEmpty
    }

    It 'preserves the raw trigger text on both parsed and unparsed results' {
        $sentence = 'Valid values are `a`, `b`.'
        (ConvertFrom-PfbValueEnumProse -TriggerSentence $sentence).TriggerText | Should -Be $sentence
    }
}

Describe 'Get-PfbSchemaPropertyDescriptions' {
    BeforeAll {
        $script:testSpec = [PSCustomObject]@{
            components = [PSCustomObject]@{
                schemas = [PSCustomObject]@{
                    BaseResource  = [PSCustomObject]@{
                        type       = 'object'
                        properties = [PSCustomObject]@{
                            id   = [PSCustomObject]@{ type = 'string'; description = 'The resource identifier.' }
                            name = [PSCustomObject]@{ type = 'string' }
                        }
                    }
                    ResourcePatch = [PSCustomObject]@{
                        allOf = @(
                            [PSCustomObject]@{ '$ref' = '#/components/schemas/BaseResource' }
                            [PSCustomObject]@{
                                type       = 'object'
                                properties = [PSCustomObject]@{
                                    enabled = [PSCustomObject]@{ type = 'boolean'; description = 'Valid values are `true` and `false`.' }
                                }
                            }
                        )
                    }
                    ListWrapper   = [PSCustomObject]@{
                        type       = 'object'
                        properties = [PSCustomObject]@{
                            tags = [PSCustomObject]@{
                                type  = 'array'
                                items = [PSCustomObject]@{ type = 'string'; description = 'Valid values are `a`, `b`.' }
                            }
                        }
                    }
                }
            }
        }
    }

    It 'reads direct property descriptions off an inline schema' {
        $schema = [PSCustomObject]@{
            properties = [PSCustomObject]@{
                a = [PSCustomObject]@{ description = 'first' }
                b = [PSCustomObject]@{ description = 'second' }
            }
        }
        $descriptions = Get-PfbSchemaPropertyDescriptions -Schema $schema -Spec $testSpec
        $descriptions['a'] | Should -Be 'first'
        $descriptions['b'] | Should -Be 'second'
    }

    It 'resolves a $ref schema before reading property descriptions' {
        $schema = [PSCustomObject]@{ '$ref' = '#/components/schemas/BaseResource' }
        $descriptions = Get-PfbSchemaPropertyDescriptions -Schema $schema -Spec $testSpec
        $descriptions['id'] | Should -Be 'The resource identifier.'
    }

    It 'merges descriptions across allOf branches, including $ref branches' {
        $schema = [PSCustomObject]@{ '$ref' = '#/components/schemas/ResourcePatch' }
        $descriptions = Get-PfbSchemaPropertyDescriptions -Schema $schema -Spec $testSpec
        $descriptions['id'] | Should -Be 'The resource identifier.'
        $descriptions['enabled'] | Should -Be 'Valid values are `true` and `false`.'
    }

    It 'descends into an array property''s items schema for its description' {
        $descriptions = Get-PfbSchemaPropertyDescriptions -Schema $testSpec.components.schemas.ListWrapper -Spec $testSpec
        $descriptions['tags'] | Should -Be 'Valid values are `a`, `b`.'
    }

    It 'omits properties with no resolvable description' {
        $schema = [PSCustomObject]@{ '$ref' = '#/components/schemas/BaseResource' }
        $descriptions = Get-PfbSchemaPropertyDescriptions -Schema $schema -Spec $testSpec
        $descriptions.ContainsKey('name') | Should -BeFalse
    }

    It 'returns an empty hashtable for a null schema' {
        (Get-PfbSchemaPropertyDescriptions -Schema $null -Spec $testSpec).Count | Should -Be 0
    }
}

Describe 'Get-PfbSpecValueEnums' {
    BeforeAll {
        # Regression fixture: two distinct schemas share the property name "access"
        # with non-identical value lists (the squash-mode gotcha). Must never collapse.
        $script:squashSpec = [PSCustomObject]@{
            components = [PSCustomObject]@{
                schemas    = [PSCustomObject]@{
                    NfsExportPolicyRuleBase                       = [PSCustomObject]@{
                        type       = 'object'
                        properties = [PSCustomObject]@{
                            access = [PSCustomObject]@{
                                type        = 'string'
                                description = 'Specifies access control for the export. Valid values are `root-squash`, `all-squash`, and `no-squash`.'
                            }
                        }
                    }
                    _presetWorkloadExportConfigurationNfsRule     = [PSCustomObject]@{
                        type       = 'object'
                        properties = [PSCustomObject]@{
                            access = [PSCustomObject]@{
                                type        = 'string'
                                description = 'Specifies access control for the export. Valid values are `root-squash`, `all-squash`, and `no-root-squash`.'
                            }
                        }
                    }
                    Bucket                                        = [PSCustomObject]@{
                        allOf = @(
                            [PSCustomObject]@{
                                type       = 'object'
                                properties = [PSCustomObject]@{
                                    versioning = [PSCustomObject]@{
                                        type        = 'string'
                                        description = 'The versioning state for objects within the bucket. Valid values are `none`, `enabled`, and `suspended`.'
                                    }
                                }
                            }
                        )
                    }
                    UnparseableThing                               = [PSCustomObject]@{
                        type       = 'object'
                        properties = [PSCustomObject]@{
                            weirdField = [PSCustomObject]@{
                                type        = 'string'
                                description = "Valid values are`nin the range of 300000 and 10800000."
                            }
                        }
                    }
                }
                parameters = [PSCustomObject]@{
                    ArrayPerformanceProtocol = [PSCustomObject]@{
                        name        = 'protocol'
                        'in'        = 'query'
                        description = 'Filter by protocol. Valid values are `nfs`, `smb`, `http`, and `s3`.'
                    }
                    sort = [PSCustomObject]@{
                        name        = 'sort'
                        'in'        = 'query'
                        description = 'Sort field. Possible values include `name`, `id`.'
                    }
                    plain = [PSCustomObject]@{
                        name        = 'plain'
                        'in'        = 'query'
                        description = 'An ordinary parameter with no enumeration.'
                    }
                }
            }
        }

        $script:results = Get-PfbSpecValueEnums -Spec $squashSpec
    }

    It 'keys schema-property entries by "SchemaName.PropertyName", never bare property name' {
        ($results | Where-Object Key -eq 'NfsExportPolicyRuleBase.access') | Should -Not -BeNullOrEmpty
        ($results | Where-Object Key -eq '_presetWorkloadExportConfigurationNfsRule.access') | Should -Not -BeNullOrEmpty
    }

    It 'sets Name to the schema property name for schema-kind entries' {
        $bucket = $results | Where-Object Key -eq 'Bucket.versioning'
        $bucket.Name | Should -Be 'versioning'
    }

    It 'sets Name to the parameter''s wire "name" field, which may differ from its components.parameters dictionary key' {
        $protocolParam = $results | Where-Object Key -eq 'ArrayPerformanceProtocol'
        $protocolParam.Name | Should -Be 'protocol'
        $protocolParam.Values | Should -Be @('nfs', 'smb', 'http', 's3')
    }

    It 'never collapses two schemas sharing a property name into one entry (squash-mode gotcha)' {
        $base = $results | Where-Object Key -eq 'NfsExportPolicyRuleBase.access'
        $preset = $results | Where-Object Key -eq '_presetWorkloadExportConfigurationNfsRule.access'

        $base.Values | Should -Be @('root-squash', 'all-squash', 'no-squash')
        $preset.Values | Should -Be @('root-squash', 'all-squash', 'no-root-squash')
        $base.Values | Should -Not -Be $preset.Values
    }

    It 'Bucket.versioning regression: extracts exactly [none, enabled, suspended]' {
        $bucket = $results | Where-Object Key -eq 'Bucket.versioning'
        $bucket | Should -Not -BeNullOrEmpty
        $bucket.Values | Should -Be @('none', 'enabled', 'suspended')
        $bucket.Parsed | Should -BeTrue
    }

    It 'includes parameter-sourced entries with Kind = parameter' {
        $sort = $results | Where-Object { $_.Key -eq 'sort' -and $_.Kind -eq 'parameter' }
        $sort | Should -Not -BeNullOrEmpty
        $sort.Values | Should -Be @('name', 'id')
    }

    It 'does not emit a record for a parameter with no trigger phrase' {
        ($results | Where-Object Key -eq 'plain') | Should -BeNullOrEmpty
    }

    It 'classifies a trigger-matching but non-enumerable description as unparsed rather than dropping it' {
        $weird = $results | Where-Object Key -eq 'UnparseableThing.weirdField'
        $weird | Should -Not -BeNullOrEmpty
        $weird.Parsed | Should -BeFalse
        $weird.Values | Should -BeNullOrEmpty
        $weird.TriggerText | Should -Not -BeNullOrEmpty
    }

    It 'returns an empty list when the spec has no components' {
        $emptySpec = [PSCustomObject]@{ components = [PSCustomObject]@{} }
        Get-PfbSpecValueEnums -Spec $emptySpec | Should -BeNullOrEmpty
    }
}
