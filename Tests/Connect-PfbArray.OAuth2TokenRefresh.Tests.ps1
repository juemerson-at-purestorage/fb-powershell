#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    function New-MockHttpError {
        param([int]$StatusCode, [string]$Message = 'mock http error')
        $ex = New-Object System.Exception($Message)
        $response = [PSCustomObject]@{ StatusCode = [System.Net.HttpStatusCode]$StatusCode }
        Add-Member -InputObject $ex -MemberType NoteProperty -Name Response -Value $response -Force
        return $ex
    }
}

Describe 'Invoke-PfbOAuth2Login' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell New-PfbJwtToken { 'fake.jwt.token' }
    }

    It 'exchanges the JWT for an access token and computes ExpiresAt from expires_in' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ access_token = 'oauth-access-token'; expires_in = 3600 }
        } -ParameterFilter { $Uri -eq 'https://fb.test/oauth2/1.0/token' }

        $before = (Get-Date).ToUniversalTime()
        $result = InModuleScope PureStorageFlashBladePowerShell {
            Invoke-PfbOAuth2Login -Endpoint 'fb.test' -ClientId 'client-1' -Issuer 'myapp' `
                -KeyId 'key-1' -Username 'pureuser' -PrivateKeyFile 'C:\keys\fake.pem'
        }
        $after = (Get-Date).ToUniversalTime()

        $result.AccessToken | Should -Be 'oauth-access-token'
        $result.TtlSeconds  | Should -Be 3600
        $result.ExpiresAt   | Should -BeGreaterThan $before.AddSeconds(3599)
        $result.ExpiresAt   | Should -BeLessThan $after.AddSeconds(3601)
    }

    It 'throws a clear error when the exchange returns no access_token' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ expires_in = 3600 }
        } -ParameterFilter { $Uri -eq 'https://fb.test/oauth2/1.0/token' }

        {
            InModuleScope PureStorageFlashBladePowerShell {
                Invoke-PfbOAuth2Login -Endpoint 'fb.test' -ClientId 'client-1' -Issuer 'myapp' `
                    -KeyId 'key-1' -Username 'pureuser' -PrivateKeyFile 'C:\keys\fake.pem'
            }
        } | Should -Throw -ExpectedMessage '*returned no access_token*'
    }

    It 'throws a clear error when the token exchange HTTP call fails' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            throw 'connection refused'
        } -ParameterFilter { $Uri -eq 'https://fb.test/oauth2/1.0/token' }

        {
            InModuleScope PureStorageFlashBladePowerShell {
                Invoke-PfbOAuth2Login -Endpoint 'fb.test' -ClientId 'client-1' -Issuer 'myapp' `
                    -KeyId 'key-1' -Username 'pureuser' -PrivateKeyFile 'C:\keys\fake.pem'
            }
        } | Should -Throw -ExpectedMessage '*OAuth2 token exchange failed*'
    }

    It 'throws a clear error when JWT generation fails' {
        Mock -ModuleName PureStorageFlashBladePowerShell New-PfbJwtToken { throw 'bad private key' }

        {
            InModuleScope PureStorageFlashBladePowerShell {
                Invoke-PfbOAuth2Login -Endpoint 'fb.test' -ClientId 'client-1' -Issuer 'myapp' `
                    -KeyId 'key-1' -Username 'pureuser' -PrivateKeyFile 'C:\keys\fake.pem'
            }
        } | Should -Throw -ExpectedMessage '*Failed to generate JWT*'
    }
}
