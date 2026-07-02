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
