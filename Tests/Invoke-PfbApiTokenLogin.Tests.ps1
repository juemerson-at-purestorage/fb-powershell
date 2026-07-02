#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force
}

Describe 'Invoke-PfbApiTokenLogin' {
    It 'POSTs the api-token header to /api/login and returns x-auth-token' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
            [PSCustomObject]@{ Headers = @{ 'x-auth-token' = 'session-token-123' } }
        } -ParameterFilter { $Uri -eq 'https://fb.test/api/login' -and $Headers['api-token'] -eq 'T-fake' }

        $result = InModuleScope PureStorageFlashBladePowerShell {
            Invoke-PfbApiTokenLogin -Endpoint 'fb.test' -ApiToken 'T-fake'
        }

        $result | Should -Be 'session-token-123'
    }

    It 'throws a clear error when the login call fails' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
            throw 'connection refused'
        } -ParameterFilter { $Uri -eq 'https://fb.test/api/login' }

        { InModuleScope PureStorageFlashBladePowerShell {
            Invoke-PfbApiTokenLogin -Endpoint 'fb.test' -ApiToken 'T-fake'
        } } |
            Should -Throw -ExpectedMessage "*Authentication failed for FlashBlade 'fb.test'*"
    }
}
