#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:testPassword = ConvertTo-SecureString 'hunter2' -AsPlainText -Force
}

Describe 'Connect-PfbArray - version negotiation (post-refactor)' {
    It 'negotiates the highest supported 2.x version numerically, ignoring 1.x noise' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ versions = @('1.8', '1.9', '2.9', '2.10', '2.26') }
        } -ParameterFilter { $Uri -like '*api_version*' }

        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
            [PSCustomObject]@{ Headers = @{ 'x-auth-token' = 'tok' } }
        } -ParameterFilter { $Uri -eq 'https://fb.test/api/login' }

        $conn = Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake'

        $conn.ApiVersion | Should -Be '2.26'
    }

    It 'throws when the array supports no REST API 2.x versions at all' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ versions = @('1.8', '1.9') }
        } -ParameterFilter { $Uri -like '*api_version*' }

        { Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake' } |
            Should -Throw -ExpectedMessage '*No REST API 2.x versions supported*'
    }
}

Describe 'Connect-PfbArray - native login version gate + Posh-SSH fallback' {

    Context 'Array supports native login (>= 2.26)' {
        It 'uses the native /api/login path and never invokes the SSH fallback' {
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
                [PSCustomObject]@{ versions = @('2.20', '2.25', '2.26') }
            } -ParameterFilter { $Uri -like '*api_version*' }

            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
                [PSCustomObject]@{ Headers = @{ 'x-auth-token' = 'native-token' } }
            } -ParameterFilter { $Uri -eq 'https://fb.test/api/login' }

            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
                throw 'no admin token available'
            } -ParameterFilter { $Uri -like '*admins/api-tokens*' }

            Mock -ModuleName PureStorageFlashBladePowerShell Get-PfbApiTokenViaSsh { throw 'should not be called' }

            $conn = Connect-PfbArray -Endpoint 'fb.test' -Username 'pureuser' -Password $script:testPassword

            $conn.AuthToken | Should -Be 'native-token'
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Get-PfbApiTokenViaSsh -Times 0
        }
    }

    Context 'Array does not support native login (< 2.26)' {
        It 'falls back to Get-PfbApiTokenViaSsh and completes login with the minted token' {
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
                [PSCustomObject]@{ versions = @('1.10', '1.11', '1.12', '2.20', '2.25') }
            } -ParameterFilter { $Uri -like '*api_version*' }

            Mock -ModuleName PureStorageFlashBladePowerShell Get-PfbApiTokenViaSsh { 'T-minted-via-ssh' }

            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
                [PSCustomObject]@{ Headers = @{ 'x-auth-token' = 'ssh-session-token' } }
            } -ParameterFilter { $Uri -eq 'https://fb.test/api/login' -and $Headers['api-token'] -eq 'T-minted-via-ssh' }

            $conn = Connect-PfbArray -Endpoint 'fb.test' -Username 'pureuser' -Password $script:testPassword

            $conn.AuthToken | Should -Be 'ssh-session-token'
            $conn.ApiToken  | Should -Be 'T-minted-via-ssh'
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Get-PfbApiTokenViaSsh -Times 1 -Exactly
        }
    }

    Context 'SSH fallback fails' {
        It 'throws a comprehensive error covering both the version gap and the SSH failure' {
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
                [PSCustomObject]@{ versions = @('2.20', '2.25') }
            } -ParameterFilter { $Uri -like '*api_version*' }

            Mock -ModuleName PureStorageFlashBladePowerShell Get-PfbApiTokenViaSsh {
                throw "The Posh-SSH module is required for SSH-based API token generation but is not installed."
            }

            { Connect-PfbArray -Endpoint 'fb.test' -Username 'pureuser' -Password $script:testPassword } |
                Should -Throw -ExpectedMessage '*Posh-SSH module is required*'
        }
    }

    Context '-ApiToken parameter set is unaffected' {
        It 'authenticates via Invoke-PfbApiTokenLogin regardless of array version' {
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
                [PSCustomObject]@{ versions = @('1.10', '1.11', '1.12', '2.20', '2.25') }
            } -ParameterFilter { $Uri -like '*api_version*' }

            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
                [PSCustomObject]@{ Headers = @{ 'x-auth-token' = 'apitoken-session' } }
            } -ParameterFilter { $Uri -eq 'https://fb.test/api/login' }

            Mock -ModuleName PureStorageFlashBladePowerShell Get-PfbApiTokenViaSsh { throw 'should not be called' }

            $conn = Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake-token'

            $conn.AuthToken | Should -Be 'apitoken-session'
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Get-PfbApiTokenViaSsh -Times 0
        }
    }
}
