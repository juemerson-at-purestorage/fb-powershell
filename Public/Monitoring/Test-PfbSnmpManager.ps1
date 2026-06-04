function Test-PfbSnmpManager {
    <#
    .SYNOPSIS
        Tests an SNMP manager configuration on a FlashBlade array.
    .DESCRIPTION
        The Test-PfbSnmpManager cmdlet tests the connectivity and configuration of an SNMP
        manager on the connected Pure Storage FlashBlade.
    .PARAMETER Name
        The name of the SNMP manager to test.
    .PARAMETER Id
        The ID of the SNMP manager to test.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Test-PfbSnmpManager -Name "snmp-mgr-01"

        Tests the SNMP manager named "snmp-mgr-01".
    .EXAMPLE
        Test-PfbSnmpManager -Id "10314f42-020d-7080-8013-000ddt400012"

        Tests the SNMP manager by ID.
    .EXAMPLE
        Test-PfbSnmpManager -Name "snmp-mgr-01" | Select-Object result_details

        Tests the SNMP manager and displays detailed results.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory)] [string]$Name,
        [Parameter(ParameterSetName = 'ById', Mandatory)] [string]$Id,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $queryParams = @{}
    if ($Name) { $queryParams['names'] = $Name }
    if ($Id) { $queryParams['ids'] = $Id }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'snmp-managers/test' -QueryParams $queryParams
}
