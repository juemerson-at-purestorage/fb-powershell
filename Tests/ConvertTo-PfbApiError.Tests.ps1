#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    function New-ErrorRecordWithBody {
        param(
            [string]$Body,
            [string]$Message = 'mock http error'
        )
        $ex = New-Object System.Exception($Message)
        $errorRecord = New-Object System.Management.Automation.ErrorRecord(
            $ex, 'MockError', [System.Management.Automation.ErrorCategory]::NotSpecified, $null)
        $errorRecord.ErrorDetails = New-Object System.Management.Automation.ErrorDetails($Body)
        return $errorRecord
    }
}

Describe 'ConvertTo-PfbApiError' {
    It 'extracts the message from a plural .errors[] body' {
        $errorRecord = New-ErrorRecordWithBody -Body '{"errors":[{"code":401,"context":"/api/2.26/arrays","message":"Invalid session token."}]}'

        $result = InModuleScope PureStorageFlashBladePowerShell -Parameters @{ errorRecord = $errorRecord } {
            ConvertTo-PfbApiError -Method 'GET' -Endpoint 'arrays' -ErrorRecord $errorRecord
        }

        $result | Should -Be 'FlashBlade API error: Invalid session token.'
    }

    It 'extracts the message from a singular .error[] body (real FlashBlade 4.8.2 shape)' {
        # Live testing against a real FlashBlade array (Purity//FB 4.8.2 / REST 2.26) proved that its
        # error responses use the singular key "error" (still an array of objects), not the plural
        # "errors" this function previously assumed exclusively:
        # {"error":[{"code":403,"context":"/api/2.26/arrays","message":"Access Denied"}]}
        $errorRecord = New-ErrorRecordWithBody -Body '{"error":[{"code":403,"context":"/api/2.26/arrays","message":"Access Denied"}]}'

        $result = InModuleScope PureStorageFlashBladePowerShell -Parameters @{ errorRecord = $errorRecord } {
            ConvertTo-PfbApiError -Method 'GET' -Endpoint 'arrays' -ErrorRecord $errorRecord
        }

        $result | Should -Be 'FlashBlade API error: Access Denied'
    }

    It 'prefers the plural .errors[] key when both .errors and .error are somehow present' {
        $errorRecord = New-ErrorRecordWithBody -Body '{"errors":[{"code":400,"message":"plural wins"}],"error":[{"code":400,"message":"singular loses"}]}'

        $result = InModuleScope PureStorageFlashBladePowerShell -Parameters @{ errorRecord = $errorRecord } {
            ConvertTo-PfbApiError -Method 'GET' -Endpoint 'arrays' -ErrorRecord $errorRecord
        }

        $result | Should -Be 'FlashBlade API error: plural wins'
    }
}
