#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Unit tests for tools/lib/PfbSpecTools.ps1 — the shared spec-extraction and
    capability-diffing helpers used by tools/Update-PfbApiSpecs.ps1 and
    tools/Build-PfbCapabilityMap.ps1.
.DESCRIPTION
    These are pure-function unit tests against a small synthetic fixture
    (Tests/Fixtures/sample-redoc-page.html) and inline synthetic spec objects — no
    network access and no dependency on the real cached specs in tools/specs/.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'tools/lib/PfbSpecTools.ps1')

    $fixturePath = Join-Path $PSScriptRoot 'Fixtures/sample-redoc-page.html'
    $script:fixtureHtml = Get-Content -Path $fixturePath -Raw
}

Describe 'ConvertFrom-PfbRedocHtml' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    # ConvertFrom-PfbRedocHtml (tools/lib/PfbSpecTools.ps1) calls ConvertFrom-Json -Depth,
    # which does not exist on Windows PowerShell 5.1 (added in PS6) -- this function is
    # dev/CI-only tooling never loaded by the shipped module (see PureStorageFlashBladePowerShell.psm1,
    # which only sources Private/ and Public/), so it's out of scope for 5.1 support.
    It 'extracts the embedded OpenAPI document' {
        $spec = ConvertFrom-PfbRedocHtml -Html $fixtureHtml
        $spec.openapi | Should -Be '3.0.1'
        $spec.info.version | Should -Be '9.9'
    }

    It 'correctly walks past braces embedded inside string values (does not truncate early)' {
        # The fixture's description contains a literal "{this}" and the trailing
        # options.theme.spacing value contains "({ spacing }) => 10" — both would break
        # a naive scan for the *first* unmatched-looking '}' instead of a real
        # string-aware balanced-brace scan.
        $spec = ConvertFrom-PfbRedocHtml -Html $fixtureHtml
        $spec.info.description | Should -Match 'braces like \{this\} embedded'
        $spec.paths.'/api/9.9/widgets' | Should -Not -BeNullOrEmpty
    }

    It 'correctly handles escaped quotes and backslashes inside strings' {
        $spec = ConvertFrom-PfbRedocHtml -Html $fixtureHtml
        $spec.info.'x-fixture-escape-test' | Should -Match 'a quoted word'
        $spec.info.'x-fixture-escape-test' | Should -Match '\\'
    }

    It 'decodes non-ASCII characters correctly' {
        $spec = ConvertFrom-PfbRedocHtml -Html $fixtureHtml
        $spec.info.description | Should -Match 'café'
    }

    It 'throws a clear error when the __redoc_state marker is missing' {
        { ConvertFrom-PfbRedocHtml -Html '<html><body>nothing here</body></html>' } |
            Should -Throw '*__redoc_state*'
    }

    It 'throws a clear error when the JSON is malformed' {
        # 'undefined' is not a valid JSON literal in any parser (unlike a trailing
        # comma, which some parsers tolerate) - this is unambiguously invalid.
        $badHtml = '<script>const __redoc_state = {"spec": {"data": undefined}};</script>'
        { ConvertFrom-PfbRedocHtml -Html $badHtml } | Should -Throw
    }
}

Describe 'ConvertTo-PfbNormalizedPath' {
    It 'strips the "/api/<version>/" prefix from versioned paths' {
        ConvertTo-PfbNormalizedPath -Path '/api/2.27/arrays' | Should -Be '/arrays'
        ConvertTo-PfbNormalizedPath -Path '/api/2.0/file-systems' | Should -Be '/file-systems'
    }

    It 'leaves unversioned auth/meta endpoints unchanged' {
        ConvertTo-PfbNormalizedPath -Path '/api/login' | Should -Be '/api/login'
        ConvertTo-PfbNormalizedPath -Path '/api/api_version' | Should -Be '/api/api_version'
        ConvertTo-PfbNormalizedPath -Path '/oauth2/1.0/token' | Should -Be '/oauth2/1.0/token'
    }
}

Describe 'Resolve-PfbRef' {
    BeforeAll {
        $script:testSpec = [PSCustomObject]@{
            components = [PSCustomObject]@{
                parameters = [PSCustomObject]@{
                    Names = [PSCustomObject]@{ name = 'names'; in = 'query' }
                }
                schemas    = [PSCustomObject]@{
                    Widget      = [PSCustomObject]@{ '$ref' = '#/components/schemas/WidgetAlias' }
                    WidgetAlias = [PSCustomObject]@{ type = 'object'; properties = [PSCustomObject]@{ id = @{ type = 'string' } } }
                }
            }
        }
    }

    It 'resolves a single-level $ref' {
        $node = [PSCustomObject]@{ '$ref' = '#/components/parameters/Names' }
        $resolved = Resolve-PfbRef -Node $node -Spec $testSpec
        $resolved.name | Should -Be 'names'
    }

    It 'follows chained $refs to the final target' {
        $node = [PSCustomObject]@{ '$ref' = '#/components/schemas/Widget' }
        $resolved = Resolve-PfbRef -Node $node -Spec $testSpec
        $resolved.type | Should -Be 'object'
    }

    It 'returns non-$ref nodes unchanged' {
        $node = [PSCustomObject]@{ name = 'plain'; in = 'query' }
        $resolved = Resolve-PfbRef -Node $node -Spec $testSpec
        $resolved.name | Should -Be 'plain'
    }

    It 'returns $null unchanged' {
        Resolve-PfbRef -Node $null -Spec $testSpec | Should -BeNullOrEmpty
    }
}

Describe 'Get-PfbSchemaPropertyNames' {
    BeforeAll {
        $script:testSpec = [PSCustomObject]@{
            components = [PSCustomObject]@{
                schemas = [PSCustomObject]@{
                    BaseResource  = [PSCustomObject]@{
                        type       = 'object'
                        properties = [PSCustomObject]@{ id = @{ type = 'string' }; name = @{ type = 'string' } }
                    }
                    ResourcePatch = [PSCustomObject]@{
                        allOf = @(
                            [PSCustomObject]@{ '$ref' = '#/components/schemas/BaseResource' }
                            [PSCustomObject]@{
                                type       = 'object'
                                properties = [PSCustomObject]@{ enabled = @{ type = 'boolean' } }
                            }
                        )
                    }
                }
            }
        }
    }

    It 'reads direct properties off an inline schema' {
        $schema = [PSCustomObject]@{ properties = [PSCustomObject]@{ a = @{}; b = @{} } }
        $names = Get-PfbSchemaPropertyNames -Schema $schema -Spec $testSpec
        $names | Should -Contain 'a'
        $names | Should -Contain 'b'
    }

    It 'resolves a $ref schema before reading properties' {
        $schema = [PSCustomObject]@{ '$ref' = '#/components/schemas/BaseResource' }
        $names = Get-PfbSchemaPropertyNames -Schema $schema -Spec $testSpec
        $names | Should -Contain 'id'
        $names | Should -Contain 'name'
    }

    It 'merges properties across allOf branches, including $ref branches' {
        $schema = [PSCustomObject]@{ '$ref' = '#/components/schemas/ResourcePatch' }
        $names = Get-PfbSchemaPropertyNames -Schema $schema -Spec $testSpec
        $names | Should -Contain 'id'
        $names | Should -Contain 'name'
        $names | Should -Contain 'enabled'
    }

    It 'returns an empty list for a null schema' {
        Get-PfbSchemaPropertyNames -Schema $null -Spec $testSpec | Should -BeNullOrEmpty
    }
}

Describe 'Get-PfbSpecCapabilities' {
    BeforeAll {
        $script:testSpec = [PSCustomObject]@{
            paths      = [PSCustomObject]@{
                '/api/9.9/widgets' = [PSCustomObject]@{
                    'x-pure-authorization-resource' = 'widgets'
                    get                              = [PSCustomObject]@{
                        parameters = @(
                            [PSCustomObject]@{ '$ref' = '#/components/parameters/Filter' }
                        )
                    }
                    post                             = [PSCustomObject]@{
                        requestBody = [PSCustomObject]@{
                            content = [PSCustomObject]@{
                                'application/json' = [PSCustomObject]@{
                                    schema = [PSCustomObject]@{ '$ref' = '#/components/schemas/WidgetPost' }
                                }
                            }
                        }
                    }
                }
            }
            components = [PSCustomObject]@{
                parameters = [PSCustomObject]@{
                    Filter = [PSCustomObject]@{ name = 'filter'; in = 'query' }
                }
                schemas    = [PSCustomObject]@{
                    WidgetPost = [PSCustomObject]@{
                        type       = 'object'
                        properties = [PSCustomObject]@{ name = @{ type = 'string' }; color = @{ type = 'string' } }
                    }
                }
            }
        }
    }

    It 'skips vendor extension keys like x-pure-authorization-resource' {
        $caps = Get-PfbSpecCapabilities -Spec $testSpec
        ($caps | ForEach-Object { $_.Method }) | Should -Not -Contain 'X-PURE-AUTHORIZATION-RESOURCE'
    }

    It 'produces one record per (method, normalized path)' {
        $caps = Get-PfbSpecCapabilities -Spec $testSpec
        $caps.Count | Should -Be 2
        ($caps | Where-Object Method -eq 'GET').Path | Should -Be '/widgets'
        ($caps | Where-Object Method -eq 'POST').Path | Should -Be '/widgets'
    }

    It 'resolves $ref parameters to their names' {
        $caps = Get-PfbSpecCapabilities -Spec $testSpec
        $getCap = $caps | Where-Object Method -eq 'GET'
        $getCap.Parameters | Should -Contain 'filter'
    }

    It 'resolves $ref request-body schemas to their property names' {
        $caps = Get-PfbSpecCapabilities -Spec $testSpec
        $postCap = $caps | Where-Object Method -eq 'POST'
        $postCap.BodyProperties | Should -Contain 'name'
        $postCap.BodyProperties | Should -Contain 'color'
    }

    It 'returns an empty list for a spec with no paths' {
        $emptySpec = [PSCustomObject]@{ paths = [PSCustomObject]@{} }
        Get-PfbSpecCapabilities -Spec $emptySpec | Should -BeNullOrEmpty
    }
}

Describe 'Get-PfbSwaggerIndexVersions' {
    It 'extracts and sorts version numbers correctly, including double-digit minors' {
        $html = @'
<a href="redoc/fb2.9-api-reference.html">2.9</a>
<a href="redoc/fb2.10-api-reference.html">2.10</a>
<a href="redoc/fb2.2-api-reference.html">2.2</a>
'@
        $versions = Get-PfbSwaggerIndexVersions -IndexHtml $html
        # Numeric sort must place 2.10 after 2.9, not lexicographically before it.
        $versions | Should -Be @('2.2', '2.9', '2.10')
    }

    It 'de-duplicates repeated links' {
        $html = '<a href="redoc/fb2.5-api-reference.html">x</a><a href="redoc/fb2.5-api-reference.html">y</a>'
        $versions = Get-PfbSwaggerIndexVersions -IndexHtml $html
        $versions | Should -Be @('2.5')
    }

    It 'returns an empty list when no versions are found' {
        Get-PfbSwaggerIndexVersions -IndexHtml '<html></html>' | Should -BeNullOrEmpty
    }
}
