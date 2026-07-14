#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Unit tests for tools/lib/PfbVersionMapTools.ps1.
.DESCRIPTION
    Only the fully-specified, network-independent piece (URL derivation) is meaningfully
    testable right now. Get-PfbVersionMapEntryFromHtml's real parsing logic is an
    unverified placeholder (see its header comment) pending a working service-key
    credential for the Everpure support site, which 401s without one — these tests cover
    its documented placeholder behavior (a "Purity//FB X.Y.Z" text scan) so regressions
    are caught, not its correctness against a real page.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'tools/lib/PfbVersionMapTools.ps1')
}

Describe 'ConvertTo-PfbSupportNotesUrl' {
    It 'derives the confirmed URL pattern, stripping the dot from the version' {
        ConvertTo-PfbSupportNotesUrl -RestVersion '2.27' |
            Should -Be 'https://support.everpuredata.com/r/flashblade-release/purityfb-management-rest-api-227-release-notes'
    }

    It 'handles double-digit minor versions correctly' {
        ConvertTo-PfbSupportNotesUrl -RestVersion '2.10' |
            Should -Be 'https://support.everpuredata.com/r/flashblade-release/purityfb-management-rest-api-210-release-notes'
    }

    It 'rejects a malformed version string' {
        { ConvertTo-PfbSupportNotesUrl -RestVersion 'not-a-version' } | Should -Throw
    }
}

Describe 'Get-PfbVersionMapEntryFromHtml (placeholder parsing)' {
    It 'extracts a Purity//FB version when the pattern is present' {
        $html = '<html><body>See Purity//FB 4.8.1 for details.</body></html>'
        $entry = Get-PfbVersionMapEntryFromHtml -Html $html -RestVersion '2.26'
        $entry.purity | Should -Be '4.8.1'
    }

    It 'tolerates spacing variations around the double slash' {
        $html = 'Purity // FB 4.9.0 release'
        $entry = Get-PfbVersionMapEntryFromHtml -Html $html -RestVersion '2.27'
        $entry.purity | Should -Be '4.9.0'
    }

    It 'returns $null and warns when no pattern is found' {
        $warnings = $null
        $entry = Get-PfbVersionMapEntryFromHtml -Html '<html>nothing relevant here</html>' -RestVersion '2.26' -WarningVariable warnings -WarningAction SilentlyContinue
        $entry | Should -BeNullOrEmpty
        $warnings | Should -Not -BeNullOrEmpty
    }
}
