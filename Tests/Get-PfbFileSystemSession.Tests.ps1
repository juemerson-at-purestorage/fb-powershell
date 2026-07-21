#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../PureStorageFlashBladePowerShell.psd1" -Force
    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Get-PfbFileSystemSession' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'restricts -Protocol to the two real spec-documented values' {
        $attr = (Get-Command Get-PfbFileSystemSession).Parameters['Protocol'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $attr | Should -Not -BeNullOrEmpty
        $attr.ValidValues | Should -Be @('nfs', 'smb')
    }

    It 'rejects an invalid -Protocol value before making any API call' {
        { Get-PfbFileSystemSession -Protocol 'bogus' -Array $fakeArray } | Should -Throw
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 0 -Exactly
    }

    It 'passes valid -Protocol values through to the query string, comma-joined' {
        Get-PfbFileSystemSession -Protocol 'nfs', 'smb' -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Endpoint -eq 'file-systems/sessions' -and $QueryParams['protocols'] -eq 'nfs,smb'
        }
    }

    It 'omits -Protocol from the query string when not specified' {
        Get-PfbFileSystemSession -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            -not $QueryParams.ContainsKey('protocols')
        }
    }
}
