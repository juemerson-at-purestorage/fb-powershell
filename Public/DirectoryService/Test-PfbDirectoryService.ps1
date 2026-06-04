function Test-PfbDirectoryService {
    <#
    .SYNOPSIS
        Tests the FlashBlade directory service configuration.
    .DESCRIPTION
        The Test-PfbDirectoryService cmdlet runs a connectivity and configuration test against
        the directory service on the connected Pure Storage FlashBlade. Returns test results
        including connectivity status and any errors encountered. This is a singleton resource
        that tests the current directory service configuration.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Test-PfbDirectoryService

        Tests the directory service configuration on the connected FlashBlade.
    .EXAMPLE
        $results = Test-PfbDirectoryService; $results.success

        Tests the directory service and checks whether the test succeeded.
    .EXAMPLE
        Test-PfbDirectoryService -Array $secondArray

        Tests the directory service configuration on a specific FlashBlade connection.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'directory-services/test' -AutoPaginate
}
