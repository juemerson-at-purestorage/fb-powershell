#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Data-integrity guard: every REST version the capability map was generated from must
    have a corresponding entry in Data/PfbVersionMap.json.
.DESCRIPTION
    Data/PfbVersionMap.json is currently hand-maintained (Glean-sourced) rather than
    produced by the still-deferred tools/Update-PfbVersionMap.ps1 generator -- see that
    script's header and tools/README.md Sec.3. This test does not care how the file was
    produced; it only catches drift, e.g. a new REST version landing in
    Data/PfbCapabilityMap.json (via the weekly CI refresh) without a matching Purity//FB
    pairing being added, either by hand or by the generator once it is unblocked.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $script:capabilityMapPath = Join-Path $repoRoot 'Data/PfbCapabilityMap.json'
    $script:versionMapPath = Join-Path $repoRoot 'Data/PfbVersionMap.json'

    # ConvertFrom-Json has no -Depth parameter on Windows PowerShell 5.1 (added in PS6) --
    # 5.1's own recursion limit (100) is already far deeper than either file's shape.
    function script:ConvertFrom-PfbTestJson {
        param([Parameter(ValueFromPipeline)] [string]$InputObject)
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $InputObject | ConvertFrom-Json -Depth 5
        }
        else {
            $InputObject | ConvertFrom-Json
        }
    }
}

Describe 'Data/PfbVersionMap.json coverage (skips gracefully if the generated files are not present)' {
    It 'has an entry for every REST version the capability map was generated from' {
        if (-not (Test-Path $capabilityMapPath) -or -not (Test-Path $versionMapPath)) {
            Set-ItResult -Skipped -Because 'Data/PfbCapabilityMap.json or Data/PfbVersionMap.json not present'
            return
        }

        $capabilityMap = Get-Content -Path $capabilityMapPath -Raw | ConvertFrom-PfbTestJson
        $versionMap = Get-Content -Path $versionMapPath -Raw | ConvertFrom-PfbTestJson

        $expectedVersions = $capabilityMap.generatedFrom
        $expectedVersions | Should -Not -BeNullOrEmpty -Because 'the capability map should record which REST versions it was generated from'

        $mappedVersions = [System.Collections.Generic.HashSet[string]]::new([string[]]$versionMap.PSObject.Properties.Name)
        $missing = $expectedVersions | Where-Object { -not $mappedVersions.Contains($_) }

        $missing | Should -BeNullOrEmpty -Because "these REST versions are in the capability map but have no Purity//FB pairing in Data/PfbVersionMap.json: $($missing -join ', ')"
    }

    It 'every entry has a non-empty purity property' {
        if (-not (Test-Path $versionMapPath)) {
            Set-ItResult -Skipped -Because 'Data/PfbVersionMap.json not present'
            return
        }

        $versionMap = Get-Content -Path $versionMapPath -Raw | ConvertFrom-PfbTestJson

        $emptyEntries = $versionMap.PSObject.Properties | Where-Object { [string]::IsNullOrWhiteSpace($_.Value.purity) } | ForEach-Object { $_.Name }

        $emptyEntries | Should -BeNullOrEmpty -Because "these REST versions have an entry but no purity value: $($emptyEntries -join ', ')"
    }
}
