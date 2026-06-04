function Test-PfbSyslogServer {
    <#
    .SYNOPSIS
        Tests a syslog server configuration on a FlashBlade array.
    .DESCRIPTION
        The Test-PfbSyslogServer cmdlet tests the connectivity and configuration of a syslog
        server on the connected Pure Storage FlashBlade.
    .PARAMETER Name
        The name of the syslog server to test.
    .PARAMETER Id
        The ID of the syslog server to test.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Test-PfbSyslogServer -Name "syslog-prod"

        Tests the syslog server named "syslog-prod".
    .EXAMPLE
        Test-PfbSyslogServer -Id "10314f42-020d-7080-8013-000ddt400012"

        Tests the syslog server by ID.
    .EXAMPLE
        Test-PfbSyslogServer -Name "syslog-prod" | Select-Object result_details

        Tests the syslog server and displays detailed results.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(ParameterSetName = 'ByName')] [string]$Name,
        [Parameter(ParameterSetName = 'ById')] [string]$Id,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $queryParams = @{}
    if ($Name) { $queryParams['names'] = $Name }
    if ($Id) { $queryParams['ids'] = $Id }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'syslog-servers/test' -QueryParams $queryParams
}
