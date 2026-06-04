function Test-PfbRapidDataLocking {
    <#
    .SYNOPSIS
        Tests the rapid data locking configuration on a FlashBlade array.
    .DESCRIPTION
        The Test-PfbRapidDataLocking cmdlet tests the rapid data locking configuration and
        connectivity on the connected Pure Storage FlashBlade. This is a singleton endpoint.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Test-PfbRapidDataLocking

        Tests the rapid data locking configuration.
    .EXAMPLE
        Test-PfbRapidDataLocking -Array $FlashBlade

        Tests the configuration using a specific FlashBlade connection.
    .EXAMPLE
        (Test-PfbRapidDataLocking).result_details

        Tests the configuration and displays detailed results.
    #>
    [CmdletBinding()]
    param([Parameter()] [PSCustomObject]$Array)
    Assert-PfbConnection -Array ([ref]$Array)
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'rapid-data-locking/test'
}
