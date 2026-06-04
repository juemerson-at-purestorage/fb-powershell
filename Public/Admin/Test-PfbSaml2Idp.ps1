function Test-PfbSaml2Idp {
    <#
    .SYNOPSIS
        Tests a SAML2 identity provider configuration on the FlashBlade.
    .DESCRIPTION
        The Test-PfbSaml2Idp cmdlet runs a connectivity and configuration test against a SAML2
        identity provider on the connected Pure Storage FlashBlade. Returns test results including
        connectivity status, metadata validation, and any errors encountered. The IdP to test
        can be identified by name or ID.
    .PARAMETER Name
        The name of the SAML2 identity provider to test.
    .PARAMETER Id
        The ID of the SAML2 identity provider to test.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Test-PfbSaml2Idp -Name "adfs-prod"

        Tests the SAML2 identity provider named "adfs-prod".
    .EXAMPLE
        Test-PfbSaml2Idp -Id "abc12345-6789-0abc-def0-123456789abc"

        Tests the SAML2 identity provider identified by ID.
    .EXAMPLE
        $results = Test-PfbSaml2Idp -Name "adfs-prod"; $results.success

        Tests the SAML2 IdP and checks whether the test succeeded.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
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

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'sso/saml2/idps/test' -QueryParams $queryParams -AutoPaginate
}
