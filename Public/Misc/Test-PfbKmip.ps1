function Test-PfbKmip {
    <#
    .SYNOPSIS
        Tests a KMIP server configuration on a FlashBlade array.
    .DESCRIPTION
        The Test-PfbKmip cmdlet tests the connectivity and configuration of a KMIP server
        on the connected Pure Storage FlashBlade.
    .PARAMETER Name
        The name of the KMIP server to test.
    .PARAMETER Id
        The ID of the KMIP server to test.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Test-PfbKmip -Name "kmip-prod"

        Tests the KMIP server named "kmip-prod".
    .EXAMPLE
        Test-PfbKmip -Id "10314f42-020d-7080-8013-000ddt400012"

        Tests the KMIP server by ID.
    .EXAMPLE
        Test-PfbKmip -Name "kmip-prod" | Select-Object result_details

        Tests the KMIP server and displays detailed results.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName')] [string]$Name,
        [Parameter(ParameterSetName = 'ById')] [string]$Id,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $queryParams = @{}
    if ($Name) { $queryParams['names'] = $Name }
    if ($Id) { $queryParams['ids'] = $Id }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'kmip/test' -QueryParams $queryParams
}
