#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'New-PfbQuotaUser' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context '-UserName path' {
        It 'POSTs quotas/users with file_system_names + user_names and a quota-only body' {
            New-PfbQuotaUser -FileSystemName 'fs-share' -UserName 'jdoe' -Quota 5368709120 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and
                $Endpoint -eq 'quotas/users' -and
                $QueryParams['file_system_names'] -eq 'fs-share' -and
                $QueryParams['user_names'] -eq 'jdoe' -and
                $Body['quota'] -eq 5368709120 -and
                $Body.Keys.Count -eq 1
            }
        }
    }

    Context '-UserId path' {
        It 'sends uids (not user_ids) and file_system_names' {
            New-PfbQuotaUser -FileSystemName 'fs-share' -UserId '1001' -Quota 1073741824 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and
                $Endpoint -eq 'quotas/users' -and
                $QueryParams['file_system_names'] -eq 'fs-share' -and
                $QueryParams['uids'] -eq '1001' -and
                $Body['quota'] -eq 1073741824
            }
        }
    }

    Context '-Attributes override (body only; identity still from query)' {
        It 'uses the attributes hashtable verbatim as the body' {
            New-PfbQuotaUser -FileSystemName 'fs-share' -UserName 'jdoe' -Attributes @{ quota = 2147483648 } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['quota'] -eq 2147483648 -and
                $QueryParams['user_names'] -eq 'jdoe' -and
                $QueryParams['file_system_names'] -eq 'fs-share'
            }
        }
    }

    Context 'regression: wrong shapes are never used' {
        It 'never sends the legacy "names" query key and never nests user/file_system in the body' {
            New-PfbQuotaUser -FileSystemName 'fs-share' -UserName 'jdoe' -Quota 100 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $QueryParams.ContainsKey('names') -and
                -not $QueryParams.ContainsKey('user_ids') -and
                -not $Body.ContainsKey('user') -and
                -not $Body.ContainsKey('file_system')
            }
        }
    }

    Context 'identity validation' {
        It 'throws when neither -UserName nor -UserId is supplied' {
            { New-PfbQuotaUser -FileSystemName 'fs-share' -Quota 100 -Confirm:$false -Array $fakeArray } |
                Should -Throw
        }

        It 'throws when both -UserName and -UserId are supplied' {
            { New-PfbQuotaUser -FileSystemName 'fs-share' -UserName 'jdoe' -UserId '1001' -Confirm:$false -Array $fakeArray } |
                Should -Throw
        }
    }

    Context 'body validation' {
        It 'throws when neither -Quota nor -Attributes is supplied' {
            { New-PfbQuotaUser -FileSystemName 'fs-share' -UserName 'jdoe' -Confirm:$false -Array $fakeArray } |
                Should -Throw
        }
    }
}
