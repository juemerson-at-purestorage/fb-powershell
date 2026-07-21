#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../PureStorageFlashBladePowerShell.psd1" -Force
    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Remove-PfbFileSystemSession' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'restricts -Protocol to the two real spec-documented values' {
        $attr = (Get-Command Remove-PfbFileSystemSession).Parameters['Protocol'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $attr | Should -Not -BeNullOrEmpty
        $attr.ValidValues | Should -Be @('nfs', 'smb')
    }

    It 'rejects an invalid -Protocol value before making any API call' {
        { Remove-PfbFileSystemSession -Name 'fs01' -Protocol 'bogus' -Confirm:$false -Array $fakeArray } | Should -Throw
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 0 -Exactly
    }

    It 'still requires -Name or -Id even with -Protocol supplied' {
        { Remove-PfbFileSystemSession -Protocol 'nfs' -Confirm:$false -Array $fakeArray } | Should -Throw
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 0 -Exactly
    }

    It 'passes valid -Protocol values through to the query string, comma-joined, alongside -Name' {
        Remove-PfbFileSystemSession -Name 'fs01' -Protocol 'nfs', 'smb' -Confirm:$false -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and $Endpoint -eq 'file-systems/sessions' -and
            $QueryParams['names'] -eq 'fs01' -and $QueryParams['protocols'] -eq 'nfs,smb'
        }
    }

    It 'passes valid -Protocol values through to the query string alongside -Id' {
        Remove-PfbFileSystemSession -Id 'abc-123' -Protocol 'smb' -Confirm:$false -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and $Endpoint -eq 'file-systems/sessions' -and
            $QueryParams['ids'] -eq 'abc-123' -and $QueryParams['protocols'] -eq 'smb'
        }
    }

    It 'omits -Protocol from the query string when not specified' {
        Remove-PfbFileSystemSession -Name 'fs01' -Confirm:$false -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            -not $QueryParams.ContainsKey('protocols')
        }
    }

    It 'honors -WhatIf (no call made)' {
        Remove-PfbFileSystemSession -Name 'fs01' -Protocol 'nfs' -WhatIf -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 0 -Exactly
    }
}
