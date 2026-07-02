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

Describe 'Invoke-PfbApiTokenLogin - TimeoutSec' {
    It 'defaults to 30 seconds when -TimeoutSec is not specified' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
            [PSCustomObject]@{ Headers = @{ 'x-auth-token' = 'tok' } }
        } -ParameterFilter { $Uri -eq 'https://fb.test/api/login' -and $TimeoutSec -eq 30 }

        InModuleScope PureStorageFlashBladePowerShell {
            Invoke-PfbApiTokenLogin -Endpoint 'fb.test' -ApiToken 'T-fake' | Out-Null
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $TimeoutSec -eq 30 }
    }

    It 'passes through an explicit -TimeoutSec' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
            [PSCustomObject]@{ Headers = @{ 'x-auth-token' = 'tok' } }
        } -ParameterFilter { $Uri -eq 'https://fb.test/api/login' -and $TimeoutSec -eq 5 }

        InModuleScope PureStorageFlashBladePowerShell {
            Invoke-PfbApiTokenLogin -Endpoint 'fb.test' -ApiToken 'T-fake' -TimeoutSec 5 | Out-Null
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $TimeoutSec -eq 5 }
    }
}

Describe 'Invoke-PfbApiTokenLogin - errors reuse ConvertTo-PfbApiError' {
    It 'includes the unpacked API error message when the array returns a structured error body' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
            $errorDetails = [System.Management.Automation.ErrorDetails]::new('{"errors":[{"message":"Invalid API token."}]}')
            $exception = [System.Exception]::new('Response status code does not indicate success: 401 ()')
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'Err', 'InvalidOperation', $null)
            $errorRecord.ErrorDetails = $errorDetails
            throw $errorRecord
        } -ParameterFilter { $Uri -eq 'https://fb.test/api/login' }

        { InModuleScope PureStorageFlashBladePowerShell {
            Invoke-PfbApiTokenLogin -Endpoint 'fb.test' -ApiToken 'T-bad'
        } } |
            Should -Throw -ExpectedMessage '*Invalid API token.*'
    }
}
