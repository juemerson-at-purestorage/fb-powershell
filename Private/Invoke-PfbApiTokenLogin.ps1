function Invoke-PfbApiTokenLogin {
    <#
    .SYNOPSIS
        Exchanges a FlashBlade API token for an x-auth-token session.
    .DESCRIPTION
        Shared by Connect-PfbArray's ApiToken parameter set and the post-SSH step of
        the Credential/PSCredential Posh-SSH fallback, via the unversioned /api/login
        endpoint, which accepts an api-token header on every FlashBlade REST version.
    .PARAMETER Endpoint
        The hostname or IP address of the FlashBlade array.
    .PARAMETER ApiToken
        The API token to exchange for a session token.
    .PARAMETER SkipCertificateCheck
        Bypass SSL certificate validation.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]$Endpoint,
        [Parameter(Mandatory)] [string]$ApiToken,
        [Parameter()] [switch]$SkipCertificateCheck
    )

    $loginParams = @{
        Method  = 'POST'
        Uri     = "https://${Endpoint}/api/login"
        Headers = @{ 'api-token' = $ApiToken }
    }
    if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
        $loginParams['SkipCertificateCheck'] = $true
    }

    try {
        $loginResponse = Invoke-WebRequest @loginParams -UseBasicParsing -ErrorAction Stop
    }
    catch {
        throw "Authentication failed for FlashBlade '${Endpoint}': $($_.Exception.Message)"
    }

    $authToken = $loginResponse.Headers['x-auth-token']
    if ($authToken -is [array]) { $authToken = $authToken[0] }
    return $authToken
}
