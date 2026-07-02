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

Describe 'Connect-PfbArray - Certificate/OAuth2 flow uses shared helper' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ versions = @('2.20', '2.25', '2.26') }
        } -ParameterFilter { $Uri -like '*api_version*' }
    }

    It 'stores the access token, expiry, ttl, and JWT-signing parameters on the connection object' {
        $expiresAt = (Get-Date).ToUniversalTime().AddHours(1)
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbOAuth2Login {
            [PSCustomObject]@{ AccessToken = 'oauth-token'; ExpiresAt = $expiresAt; TtlSeconds = 3600 }
        }

        $conn = Connect-PfbArray -Endpoint 'fb.test' -Username 'pureuser' -ClientId 'client-1' `
            -Issuer 'myapp' -KeyId 'key-1' -PrivateKeyFile 'C:\keys\fake.pem'

        $conn.AuthToken       | Should -Be 'oauth-token'
        $conn.BearerToken     | Should -Be 'oauth-token'
        $conn.TokenExpiresAt  | Should -Be $expiresAt
        $conn.TokenTtlSeconds | Should -Be 3600
        $conn.ClientId        | Should -Be 'client-1'
        $conn.Issuer          | Should -Be 'myapp'
        $conn.KeyId           | Should -Be 'key-1'
        $conn.PrivateKeyFile  | Should -Be 'C:\keys\fake.pem'
        $conn.ApiToken        | Should -BeNullOrEmpty
    }

    It 'hides ClientId, Issuer, KeyId, PrivateKeyFile, and PrivateKeyPassword from default display' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbOAuth2Login {
            [PSCustomObject]@{ AccessToken = 'oauth-token'; ExpiresAt = (Get-Date).ToUniversalTime().AddHours(1); TtlSeconds = 3600 }
        }

        $conn = Connect-PfbArray -Endpoint 'fb.test' -Username 'pureuser' -ClientId 'client-1' `
            -Issuer 'myapp' -KeyId 'key-1' -PrivateKeyFile 'C:\keys\fake.pem'

        $defaultView = ($conn | Format-List | Out-String)
        $defaultView | Should -Not -Match 'PrivateKeyPassword'
        $defaultView | Should -Not -Match 'ClientId'
        $defaultView | Should -Not -Match 'Issuer'
        $defaultView | Should -Not -Match 'KeyId'
        $defaultView | Should -Not -Match 'PrivateKeyFile'
        # Sanity check: the properties still exist and are directly reachable, just hidden from default display
        $conn.ClientId | Should -Be 'client-1'
    }

    It 'throws when Invoke-PfbOAuth2Login fails, without falling back to any other auth path' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbOAuth2Login {
            throw "OAuth2 token exchange failed for FlashBlade 'fb.test': connection refused"
        }

        { Connect-PfbArray -Endpoint 'fb.test' -Username 'pureuser' -ClientId 'client-1' `
            -Issuer 'myapp' -KeyId 'key-1' -PrivateKeyFile 'C:\keys\fake.pem' } |
            Should -Throw -ExpectedMessage '*OAuth2 token exchange failed*'
    }
}
