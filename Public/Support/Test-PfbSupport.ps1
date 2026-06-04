function Test-PfbSupport {
    <#
    .SYNOPSIS
        Tests support connectivity on a FlashBlade array.
    .DESCRIPTION
        The Test-PfbSupport cmdlet tests the support connectivity of the connected Pure Storage
        FlashBlade. This returns test results indicating whether Phone Home and remote assist
        connections are functioning properly.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Test-PfbSupport

        Runs the support connectivity test on the connected FlashBlade.
    .EXAMPLE
        Test-PfbSupport -Array $FlashBlade

        Runs the support test using a specific FlashBlade connection object.
    .EXAMPLE
        $result = Test-PfbSupport; $result.test_type

        Runs the support test and displays the test type from the results.
    #>
    [CmdletBinding()]
    param([Parameter()] [PSCustomObject]$Array)
    Assert-PfbConnection -Array ([ref]$Array)
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'support/test'
}
