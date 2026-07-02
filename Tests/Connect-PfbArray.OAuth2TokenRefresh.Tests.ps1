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

Describe 'Invoke-PfbApiRequest - Certificate/OAuth2 token refresh' {
    BeforeAll {
        function New-CertificateConnection {
            param(
                [datetime]$TokenExpiresAt,
                [int]$TokenTtlSeconds = 3600,
                [string]$AuthToken = 'initial-token'
            )
            [PSCustomObject]@{
                Endpoint              = 'fb.test'
                ApiVersion            = '2.26'
                AuthToken             = $AuthToken
                BearerToken           = $AuthToken
                ApiToken              = $null
                AuthMethod            = 'Certificate'
                ClientId              = 'client-1'
                Issuer                = 'myapp'
                KeyId                 = 'key-1'
                Username              = 'pureuser'
                PrivateKeyFile        = 'C:\keys\fake.pem'
                PrivateKeyPassword    = $null
                TokenExpiresAt        = $TokenExpiresAt
                TokenTtlSeconds       = $TokenTtlSeconds
                SkipCertificateCheck  = $false
            }
        }
    }

    Context 'Proactive refresh' {
        It 'refreshes before the call when the token is already past its buffer-adjusted expiry' {
            $array = New-CertificateConnection -TokenExpiresAt ((Get-Date).ToUniversalTime().AddMinutes(-5))

            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbOAuth2Login {
                [PSCustomObject]@{ AccessToken = 'refreshed-token'; ExpiresAt = (Get-Date).ToUniversalTime().AddHours(1); TtlSeconds = 3600 }
            }
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
                [PSCustomObject]@{ items = @() }
            } -ParameterFilter { $Uri -like '*file-systems*' }

            InModuleScope PureStorageFlashBladePowerShell -Parameters @{ array = $array } {
                Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' | Out-Null
            }

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbOAuth2Login -Times 1 -Exactly
            $array.AuthToken | Should -Be 'refreshed-token'
        }

        It 'syncs $script:PfbDefaultArray and $script:PfbArrays to the refreshed connection after a proactive refresh' {
            $array = New-CertificateConnection -TokenExpiresAt ((Get-Date).ToUniversalTime().AddMinutes(-5))
            # A distinct object with the same Endpoint but a different identity/token stands in for
            # whatever the module's cache held before this call. This proves the cache is genuinely
            # re-pointed at the refreshed $array -- merely asserting on $array.AuthToken (as the
            # sibling test above does) would pass even if the module's cache-sync code were deleted,
            # because $array itself is a reference type mutated in place regardless of caching.
            $staleCachedClone = New-CertificateConnection -TokenExpiresAt ((Get-Date).ToUniversalTime().AddMinutes(-5)) -AuthToken 'stale-cached-token'

            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbOAuth2Login {
                [PSCustomObject]@{ AccessToken = 'refreshed-token'; ExpiresAt = (Get-Date).ToUniversalTime().AddHours(1); TtlSeconds = 3600 }
            }
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
                [PSCustomObject]@{ items = @() }
            } -ParameterFilter { $Uri -like '*file-systems*' }

            InModuleScope PureStorageFlashBladePowerShell -Parameters @{ staleCachedClone = $staleCachedClone } {
                $script:PfbArrays = @{ $staleCachedClone.Endpoint = $staleCachedClone }
                $script:PfbDefaultArray = $staleCachedClone
            }

            InModuleScope PureStorageFlashBladePowerShell -Parameters @{ array = $array } {
                Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' | Out-Null
            }

            $cachedDefaultToken = InModuleScope PureStorageFlashBladePowerShell { $script:PfbDefaultArray.AuthToken }
            $cachedArraysToken  = InModuleScope PureStorageFlashBladePowerShell -Parameters @{ array = $array } { $script:PfbArrays[$array.Endpoint].AuthToken }

            $cachedDefaultToken | Should -Be 'refreshed-token'
            $cachedArraysToken  | Should -Be 'refreshed-token'
        }

        It 'does not refresh when the token is comfortably within its TTL' {
            $array = New-CertificateConnection -TokenExpiresAt ((Get-Date).ToUniversalTime().AddHours(1))

            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbOAuth2Login { throw 'should not be called' }
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
                [PSCustomObject]@{ items = @() }
            } -ParameterFilter { $Uri -like '*file-systems*' }

            InModuleScope PureStorageFlashBladePowerShell -Parameters @{ array = $array } {
                Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' | Out-Null
            }

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbOAuth2Login -Times 0
            $array.AuthToken | Should -Be 'initial-token'
        }
    }

    Context 'Buffer scaling at TTL extremes' {
        It 'scales the buffer down for a very short (1s) TTL instead of using a fixed 30s' {
            # buffer = min(30, 1 * 0.10) = 0.1s. An expiry 0.9s in the future should NOT
            # trigger a refresh yet -- a fixed 30s buffer would incorrectly say it should.
            $array = New-CertificateConnection -TokenExpiresAt ((Get-Date).ToUniversalTime().AddMilliseconds(900)) -TokenTtlSeconds 1

            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbOAuth2Login { throw 'should not be called yet' }
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
                [PSCustomObject]@{ items = @() }
            } -ParameterFilter { $Uri -like '*file-systems*' }

            InModuleScope PureStorageFlashBladePowerShell -Parameters @{ array = $array } {
                Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' | Out-Null
            }

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbOAuth2Login -Times 0
        }

        It 'caps the buffer at 30s for a long (24h) TTL instead of scaling to 2.4h' {
            $array = New-CertificateConnection -TokenExpiresAt ((Get-Date).ToUniversalTime().AddMinutes(50)) -TokenTtlSeconds 86400

            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbOAuth2Login { throw 'should not be called' }
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
                [PSCustomObject]@{ items = @() }
            } -ParameterFilter { $Uri -like '*file-systems*' }

            InModuleScope PureStorageFlashBladePowerShell -Parameters @{ array = $array } {
                Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' | Out-Null
            }

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbOAuth2Login -Times 0
        }
    }

    Context 'Reactive fallback on 401' {
        It 'refreshes and retries once when the array returns 401 despite a locally-valid token' {
            $array = New-CertificateConnection -TokenExpiresAt ((Get-Date).ToUniversalTime().AddHours(1))
            # Seeding must happen via InModuleScope: a bare $script: assignment made directly in
            # this It block would set a variable in this test file's own script scope, not the
            # module's -- $script: resolves relative to where a scriptblock is defined, and this
            # scriptblock is defined here, not inside the module. See the empirical check recorded
            # in .superpowers/sdd/task-3-report.md for confirmation.
            InModuleScope PureStorageFlashBladePowerShell -Parameters @{ array = $array } {
                $script:PfbArrays = @{ 'fb.test' = $array }
                $script:PfbDefaultArray = $array
            }

            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbOAuth2Login {
                [PSCustomObject]@{ AccessToken = 'refreshed-token'; ExpiresAt = (Get-Date).ToUniversalTime().AddHours(1); TtlSeconds = 3600 }
            }

            $script:oauthCallCount = 0
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
                $script:oauthCallCount++
                if ($script:oauthCallCount -eq 1) {
                    throw (New-MockHttpError -StatusCode 401 -Message 'unauthorized')
                }
                [PSCustomObject]@{ items = @() }
            } -ParameterFilter { $Uri -like '*file-systems*' }

            InModuleScope PureStorageFlashBladePowerShell -Parameters @{ array = $array } {
                Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' | Out-Null
            }

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbOAuth2Login -Times 1 -Exactly
            $array.AuthToken | Should -Be 'refreshed-token'
            $script:oauthCallCount | Should -Be 2
        }
    }

    Context 'Other auth methods unaffected' {
        It 'never calls Invoke-PfbOAuth2Login for an ApiToken-authenticated connection' {
            $array = [PSCustomObject]@{
                Endpoint             = 'fb.test'
                ApiVersion           = '2.26'
                AuthToken            = 'session-token'
                BearerToken          = $null
                ApiToken             = 'T-fake-token'
                AuthMethod           = 'ApiToken'
                SkipCertificateCheck = $false
            }

            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbOAuth2Login { throw 'should not be called' }
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
                [PSCustomObject]@{ items = @() }
            } -ParameterFilter { $Uri -like '*file-systems*' }

            InModuleScope PureStorageFlashBladePowerShell -Parameters @{ array = $array } {
                Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' | Out-Null
            }

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbOAuth2Login -Times 0
        }
    }
}

Describe 'Certificate/OAuth2 refresh - PrivateKeyPassword never logged' {
    It 'never surfaces the plaintext private key password in Write-Verbose or Write-Warning output' {
        $plainPassword = 'super-secret-key-password'
        $keyPassword = ConvertTo-SecureString $plainPassword -AsPlainText -Force

        $script:capturedMessages = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName PureStorageFlashBladePowerShell Write-Verbose {
            $script:capturedMessages.Add([string]$Message)
        }
        Mock -ModuleName PureStorageFlashBladePowerShell Write-Warning {
            $script:capturedMessages.Add([string]$Message)
        }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ versions = @('2.26') }
        } -ParameterFilter { $Uri -like '*api_version*' }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbOAuth2Login {
            [PSCustomObject]@{ AccessToken = 'oauth-token'; ExpiresAt = (Get-Date).ToUniversalTime().AddSeconds(-1); TtlSeconds = 60 }
        }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ items = @() }
        } -ParameterFilter { $Uri -like '*file-systems*' }

        $conn = Connect-PfbArray -Endpoint 'fb.test' -Username 'pureuser' -ClientId 'client-1' `
            -Issuer 'myapp' -KeyId 'key-1' -PrivateKeyFile 'C:\keys\fake.pem' -PrivateKeyPassword $keyPassword

        # ExpiresAt was set 1 second in the past above, so this call triggers a proactive refresh cycle too.
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ conn = $conn } {
            Invoke-PfbApiRequest -Array $conn -Method GET -Endpoint 'file-systems' | Out-Null
        }

        $joined = $script:capturedMessages -join "`n"
        $joined | Should -Not -Match ([regex]::Escape($plainPassword))
    }
}
