function Test-PfbActiveDirectory {
    <#
    .SYNOPSIS
        Tests the FlashBlade Active Directory configuration.
    .DESCRIPTION
        The Test-PfbActiveDirectory cmdlet runs a connectivity and configuration test against
        an Active Directory configuration on the connected Pure Storage FlashBlade. Returns
        test results including domain connectivity status, authentication checks, and any errors
        encountered. The AD configuration to test can be identified by name or ID.
    .PARAMETER Name
        The name of the Active Directory configuration to test.
    .PARAMETER Id
        The ID of the Active Directory configuration to test.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Test-PfbActiveDirectory -Name "ad1"

        Tests the Active Directory configuration named "ad1".
    .EXAMPLE
        Test-PfbActiveDirectory -Id "abc12345-6789-0abc-def0-123456789abc"

        Tests the Active Directory configuration identified by ID.
    .EXAMPLE
        $results = Test-PfbActiveDirectory -Name "ad1"; $results.success

        Tests the AD configuration and checks whether the test succeeded.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipelineByPropertyName)]
        [string]$Name,
        [Parameter(ParameterSetName = 'ById')] [string]$Id,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($Name) { $queryParams['names'] = $Name }
    if ($Id)   { $queryParams['ids']   = $Id }

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'active-directory/test' -QueryParams $queryParams -AutoPaginate
}
