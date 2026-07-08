#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force
}

Describe 'New-PfbJwtToken' {
    Context 'BEGIN ENCRYPTED PRIVATE KEY (PrivateKeyPassword decryption)' {
        BeforeAll {
            # Generate a real encrypted PKCS#8 key at runtime -- never committed to source control.
            # Same technique used in Tests/Connect-PfbArray.OAuth2TokenRefresh.Tests.ps1.
            $script:plainPassword = 'super-secret-jwt-test-password'
            $script:rsa = [System.Security.Cryptography.RSA]::Create(2048)
            $pbeParams = [System.Security.Cryptography.PbeParameters]::new(
                [System.Security.Cryptography.PbeEncryptionAlgorithm]::Aes256Cbc,
                [System.Security.Cryptography.HashAlgorithmName]::SHA256,
                100000)
            $keyPem = $script:rsa.ExportEncryptedPkcs8PrivateKeyPem($script:plainPassword, $pbeParams)
            $script:keyPath = Join-Path $TestDrive 'encrypted-jwt-test-key.pem'
            Set-Content -Path $script:keyPath -Value $keyPem -NoNewline
        }

        It 'mints a validly-signed JWT by decrypting the encrypted PKCS#8 private key' {
            # Regression coverage for the fix that wraps the SecureStringToBSTR/PtrToStringAuto/
            # ImportEncryptedPkcs8PrivateKey sequence in try/finally with ZeroFreeBSTR. Actually
            # inspecting whether the unmanaged BSTR was zeroed/freed isn't practically assertable
            # from black-box Pester -- a broken ZeroFreeBSTR usage (wrong pointer, double free)
            # would instead throw or corrupt the RSA import, which this functional assertion
            # would catch. So this test proves the function still mints a correct JWT end-to-end.
            $securePassword = ConvertTo-SecureString $script:plainPassword -AsPlainText -Force
            $keyPathParam = $script:keyPath

            $jwt = InModuleScope PureStorageFlashBladePowerShell -Parameters @{
                keyPathParam    = $keyPathParam
                securePassword  = $securePassword
            } {
                New-PfbJwtToken -KeyId 'key-1' -ClientId 'client-1' -Issuer 'myapp' `
                    -Username 'pureuser' -PrivateKeyFile $keyPathParam -PrivateKeyPassword $securePassword
            }

            $jwt | Should -Not -BeNullOrEmpty
            $parts = $jwt -split '\.'
            $parts.Count | Should -Be 3

            # Decode header and payload to confirm the claims round-tripped correctly.
            function ConvertFrom-Base64Url {
                param([string]$Text)
                $padded = $Text.Replace('-', '+').Replace('_', '/')
                switch ($padded.Length % 4) {
                    2 { $padded += '==' }
                    3 { $padded += '=' }
                }
                [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($padded))
            }

            $header  = ConvertFrom-Base64Url $parts[0] | ConvertFrom-Json
            $payload = ConvertFrom-Base64Url $parts[1] | ConvertFrom-Json

            $header.alg  | Should -Be 'RS256'
            $header.kid  | Should -Be 'key-1'
            $payload.aud | Should -Be 'client-1'
            $payload.iss | Should -Be 'myapp'
            $payload.sub | Should -Be 'pureuser'

            # Verify the signature is actually valid for the unsigned header.payload against the
            # public key -- proves the correct private key was successfully decrypted and used.
            $unsigned = "$($parts[0]).$($parts[1])"
            $dataBytes = [System.Text.Encoding]::UTF8.GetBytes($unsigned)
            # Base64url-decode the signature to raw bytes directly (not via the UTF8 text helper
            # above, which would corrupt binary signature data).
            $padded = $parts[2].Replace('-', '+').Replace('_', '/')
            switch ($padded.Length % 4) {
                2 { $padded += '==' }
                3 { $padded += '=' }
            }
            $signatureBytes = [Convert]::FromBase64String($padded)

            $isValid = $script:rsa.VerifyData($dataBytes, $signatureBytes, `
                [System.Security.Cryptography.HashAlgorithmName]::SHA256, `
                [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
            $isValid | Should -BeTrue
        }

        It 'throws when the encrypted key is provided without a PrivateKeyPassword' {
            $keyPathParam = $script:keyPath

            {
                InModuleScope PureStorageFlashBladePowerShell -Parameters @{
                    keyPathParam = $keyPathParam
                } {
                    New-PfbJwtToken -KeyId 'key-1' -ClientId 'client-1' -Issuer 'myapp' `
                        -Username 'pureuser' -PrivateKeyFile $keyPathParam
                }
            } | Should -Throw -ExpectedMessage '*Provide -PrivateKeyPassword*'
        }
    }
}
