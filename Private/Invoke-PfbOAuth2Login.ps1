function Invoke-PfbOAuth2Login {
    <#
    .SYNOPSIS
        Mints a JWT and exchanges it for an OAuth2 access token from a FlashBlade array.
    .DESCRIPTION
        Shared by Connect-PfbArray's initial Certificate-flow login and the automatic
        token-refresh logic in Invoke-PfbApiRequest, so the JWT-mint-and-exchange logic
        exists in exactly one place.
    .PARAMETER Endpoint
        The hostname or IP address of the FlashBlade array.
    .PARAMETER ClientId
        Client ID of the API client registered on the FlashBlade.
    .PARAMETER Issuer
        The identity provider issuer string. Used as the JWT 'iss' claim.
    .PARAMETER KeyId
        Key ID of the API client. Used as the JWT 'kid' header claim.
    .PARAMETER Username
        The array user to act as. Used as the JWT 'sub' claim.
    .PARAMETER PrivateKeyFile
        Path to the PEM-encoded RSA private key file.
    .PARAMETER PrivateKeyPassword
        Password for an encrypted private key file, if applicable.
    .PARAMETER SkipCertificateCheck
        Bypass SSL certificate validation for the token-exchange call.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)] [string]$Endpoint,
        [Parameter(Mandatory)] [string]$ClientId,
        [Parameter(Mandatory)] [string]$Issuer,
        [Parameter(Mandatory)] [string]$KeyId,
        [Parameter(Mandatory)] [string]$Username,
        [Parameter(Mandatory)] [string]$PrivateKeyFile,
        [Parameter()] [System.Security.SecureString]$PrivateKeyPassword,
        [Parameter()] [switch]$SkipCertificateCheck
    )

    $jwtParams = @{
        KeyId          = $KeyId
        ClientId       = $ClientId
        Issuer         = $Issuer
        Username       = $Username
        PrivateKeyFile = $PrivateKeyFile
    }
    if ($PrivateKeyPassword) {
        $jwtParams['PrivateKeyPassword'] = $PrivateKeyPassword
    }

    try {
        $jwt = New-PfbJwtToken @jwtParams
    }
    catch {
        throw "Failed to generate JWT for OAuth2 authentication: $($_.Exception.Message)"
    }

    $oauthBody = "grant_type=urn:ietf:params:oauth:grant-type:token-exchange&subject_token=${jwt}&subject_token_type=urn:ietf:params:oauth:token-type:jwt"
    $oauthParams = @{
        Method      = 'POST'
        Uri         = "https://${Endpoint}/oauth2/1.0/token"
        Body        = $oauthBody
        ContentType = 'application/x-www-form-urlencoded'
    }
    if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
        $oauthParams['SkipCertificateCheck'] = $true
    }

    try {
        $oauthResponse = Invoke-RestMethod @oauthParams -ErrorAction Stop
    }
    catch {
        throw "OAuth2 token exchange failed for FlashBlade '${Endpoint}': $($_.Exception.Message)"
    }

    $bearerToken = $oauthResponse.access_token
    if ([string]::IsNullOrEmpty($bearerToken)) {
        throw "OAuth2 token exchange returned no access_token from FlashBlade '${Endpoint}'."
    }

    $ttlSeconds = $oauthResponse.expires_in
    $expiresAt = (Get-Date).ToUniversalTime().AddSeconds($ttlSeconds)

    return [PSCustomObject]@{
        AccessToken = $bearerToken
        ExpiresAt   = $expiresAt
        TtlSeconds  = $ttlSeconds
    }
}
