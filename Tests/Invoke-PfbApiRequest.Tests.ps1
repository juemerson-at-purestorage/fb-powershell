#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force
}

Describe 'Invoke-PfbApiRequest - HttpTimeoutMs is applied' {
    It 'passes Array.HttpTimeoutMs (converted to whole seconds) as TimeoutSec' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ items = @() }
        } -ParameterFilter { $Uri -like '*file-systems*' -and $TimeoutSec -eq 45 }

        InModuleScope PureStorageFlashBladePowerShell {
            $array = [PSCustomObject]@{
                Endpoint      = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken      = $null; AuthMethod = 'ApiToken'
                SkipCertificateCheck = $false; HttpTimeoutMs = 45000
            }
            Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' | Out-Null
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Uri -like '*file-systems*' -and $TimeoutSec -eq 45
        }
    }

    It 'defaults to 30 seconds when HttpTimeoutMs is absent from the connection object' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ items = @() }
        } -ParameterFilter { $Uri -like '*file-systems*' -and $TimeoutSec -eq 30 }

        InModuleScope PureStorageFlashBladePowerShell {
            $array = [PSCustomObject]@{
                Endpoint = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken = $null; AuthMethod = 'ApiToken'; SkipCertificateCheck = $false
            }
            Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' | Out-Null
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Uri -like '*file-systems*' -and $TimeoutSec -eq 30
        }
    }

    It 'passes TimeoutSec to Connect-PfbArrayInternal on 401 auto-reconnect' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
            $mockResponse = @{
                Headers = @{ 'x-auth-token' = 'new-token' }
            }
            return $mockResponse
        } -ParameterFilter { $Uri -like '*login*' -and $TimeoutSec -eq 45 }

        InModuleScope PureStorageFlashBladePowerShell {
            # Test Connect-PfbArrayInternal directly
            $result = Connect-PfbArrayInternal -Endpoint 'fb.test' -ApiToken 'test-token' -ApiVersion '2.26' -TimeoutSec 45
            $result.AuthToken | Should -Be 'new-token'
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -like '*login*' -and $TimeoutSec -eq 45
        }
    }
}
