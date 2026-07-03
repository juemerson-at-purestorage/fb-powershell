#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../PureStorageFlashBladePowerShell.psd1" -Force
    # A throwaway connection object; Assert-PfbConnection is mocked so its contents don't matter.
    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'New-PfbFileSystemSnapshot' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'makes one API call with joined source_names for explicit -SourceName' {
        New-PfbFileSystemSnapshot -SourceName 'fs1', 'fs2' -Confirm:$false -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Endpoint -eq 'file-system-snapshots' -and $QueryParams['source_names'] -eq 'fs1,fs2'
        }
    }

    It 'accumulates ALL piped FileSystem objects into ONE call (regression: not just the last)' {
        $fsObjects = @(
            [pscustomobject]@{ name = 'fs1' }
            [pscustomobject]@{ name = 'fs2' }
            [pscustomobject]@{ name = 'fs3' }
        )
        $fsObjects | New-PfbFileSystemSnapshot -Confirm:$false -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $QueryParams['source_names'] -eq 'fs1,fs2,fs3'
        }
    }

    It 'passes suffix in the body when -Suffix is supplied' {
        New-PfbFileSystemSnapshot -SourceName 'fs1' -Suffix 'daily-backup' -Confirm:$false -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Body['suffix'] -eq 'daily-backup'
        }
    }

    It 'makes zero API calls under -WhatIf' {
        New-PfbFileSystemSnapshot -SourceName 'fs1' -WhatIf -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 0 -Exactly
    }
}
