#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Unit tests for tools/lib/PfbVersionMapTools.ps1.
.DESCRIPTION
    Covers the SSOT (Fluid Topics proxy) fetch-URL builder and the HTML table parser,
    both fully-specified and network-independent. The orchestration in
    tools/Update-PfbVersionMap.ps1 itself (the live HTTP fetch) is not unit tested here,
    consistent with the rest of this module's tools/ scripts.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'tools/lib/PfbVersionMapTools.ps1')
}

Describe 'Get-PfbSsotVersionMapUri' {
    It 'builds the default SSOT topic-content URL' {
        Get-PfbSsotVersionMapUri |
            Should -Be 'https://***REMOVED***/v1/topics/***REMOVED***/content'
    }

    It 'honors overrides for base URI and topic ID' {
        Get-PfbSsotVersionMapUri -BaseUri 'https://example.test' -TopicId 'abc123' |
            Should -Be 'https://example.test/v1/topics/abc123/content'
    }
}

Describe 'ConvertFrom-PfbSsotVersionMapHtml' {
    It 'parses a data row into a REST version -> purity entry' {
        $html = @'
<table>
<tr><th>REST API Version</th><th>HTML</th><th>Introduced in Purity//FB</th><th>Ships with Purity//FB</th></tr>
<tr><td>REST API 2.27</td><td><a href="#">html</a></td><td>4.8.3</td><td>4.8.3</td></tr>
<tr><td>REST API 2.26</td><td><a href="#">html</a></td><td>4.8.1</td><td>4.8.1</td></tr>
</table>
'@
        $map = ConvertFrom-PfbSsotVersionMapHtml -Html $html

        $map['2.27'].purity | Should -Be '4.8.3'
        $map['2.26'].purity | Should -Be '4.8.1'
    }

    It 'uses the "Introduced in Purity//FB" column, not "Ships with", when they differ' {
        $html = '<tr><td>REST API 2.12</td><td>x</td><td>4.3.4</td><td>4.3.3</td></tr>'
        $map = ConvertFrom-PfbSsotVersionMapHtml -Html $html

        $map['2.12'].purity | Should -Be '4.3.4'
    }

    It 'strips nested tags and trims whitespace inside cells' {
        $html = '<tr><td>  <b>REST API 2.20</b>  </td><td>x</td><td> <span>4.6.3</span> </td><td>4.6.3</td></tr>'
        $map = ConvertFrom-PfbSsotVersionMapHtml -Html $html

        $map['2.20'].purity | Should -Be '4.6.3'
    }

    It 'decodes HTML entities inside cells' {
        $html = '<tr><td>REST API 2.9</td><td>x</td><td>4.2.0&nbsp;</td><td>4.2.0</td></tr>'
        $map = ConvertFrom-PfbSsotVersionMapHtml -Html $html

        $map['2.9'].purity | Should -Be '4.2.0'
    }

    It 'skips header/non-version rows that do not match the "REST API X.Y" pattern' {
        $html = @'
<tr><th>REST API Version</th><th>HTML</th><th>Introduced in Purity//FB</th><th>Ships with Purity//FB</th></tr>
<tr><td>REST API 2.27</td><td>x</td><td>4.8.3</td><td>4.8.3</td></tr>
'@
        $map = ConvertFrom-PfbSsotVersionMapHtml -Html $html

        $map.Count | Should -Be 1
        $map.Contains('2.27') | Should -BeTrue
    }

    It 'skips rows with fewer than 4 cells' {
        $html = '<tr><td>REST API 2.27</td><td>only two cells</td></tr>'
        $map = ConvertFrom-PfbSsotVersionMapHtml -Html $html

        $map.Count | Should -Be 0
    }

    It 'returns an empty map when no matching rows are present' {
        $map = ConvertFrom-PfbSsotVersionMapHtml -Html '<html><body>nothing relevant here</body></html>'

        $map.Count | Should -Be 0
    }
}
