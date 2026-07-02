function Connect-PfbArray {
    <#
    .SYNOPSIS
        Connect to a FlashBlade array.
    .DESCRIPTION
        Connect to a FlashBlade array (using supported authentication method) and get an
        access token. Mirrors the Connect-Pfa2Array experience from the FlashArray PowerShell SDK.

        Supported authentication methods:
        - API token (default)
        - Username and password (Credential parameter set)
        - PSCredential object (PSCredential parameter set)
        - OAuth2/JWT certificate-based authentication (Certificate parameter set)

        Username/Password Authentication Flow:
        When using -Password or -Credential, the cmdlet POSTs the credentials to the
        unversioned /api/login endpoint, which is the REST 2.x native username/password
        login. A session token (x-auth-token) is returned and used for subsequent calls.
        The optional long-lived API token can be retrieved from /admins/api-tokens for
        future passwordless reconnects.

        OAuth2/Certificate Authentication Flow:
        The JWT built from -ClientId/-Issuer/-KeyId/-PrivateKeyFile is a short-lived
        (5 minute) bootstrap credential used once to exchange for an OAuth2 access
        token; it is not retained. Unlike every other authentication method here,
        Certificate/OAuth2 sessions do NOT auto-reconnect when the access token
        expires — see .NOTES for why and how to work around it.

        Auto-negotiates the highest supported API version unless explicitly specified.
        The connection is cached and becomes the default for subsequent cmdlet calls.
    .PARAMETER Endpoint
        The hostname or IP address of the FlashBlade array.
    .PARAMETER ApiToken
        The API token for authentication. Generate via the FlashBlade CLI or GUI.
    .PARAMETER Username
        Login name of the array user. For Credential auth: used with -Password.
        For Certificate auth: the JWT 'sub' claim — the array user to act as.
    .PARAMETER Password
        Password for the specified username as a SecureString.
    .PARAMETER Credential
        A PSCredential object containing username and password for authentication.
    .PARAMETER ClientId
        Client ID of the API client registered on the FlashBlade.
        Used for OAuth2 certificate-based authentication.
    .PARAMETER Issuer
        The identity provider issuer string. Must match the 'issuer' field
        configured on the API client. Used as the JWT 'iss' claim.
    .PARAMETER KeyId
        Key ID of the API client. Used as the JWT 'kid' header claim.
    .PARAMETER PrivateKeyFile
        Path to the PEM-encoded RSA private key file that pairs with the
        API client's public key. Supports PKCS#1 and PKCS#8 formats.
    .PARAMETER PrivateKeyPassword
        Password for an encrypted private key file (PKCS#8 encrypted format).
        Only required if the private key is password-protected.
    .PARAMETER ApiVersion
        Force a specific API version (e.g., '2.12'). If not specified, the highest
        supported 2.x version is auto-negotiated.
    .PARAMETER IgnoreCertificateError
        Bypass SSL certificate validation. Common for lab environments with self-signed certs.
    .PARAMETER HttpTimeout
        HTTP request timeout in milliseconds. Default is 30000 (30 seconds).
    .NOTES
        Certificate/OAuth2 sessions do not auto-reconnect on token expiry.

        Every other authentication method (-ApiToken, -Password, -Credential) caches a
        long-lived API token on the connection object, so Invoke-PfbApiRequest can
        silently mint a fresh session token if a call gets a 401. The Certificate
        parameter set has no equivalent: the connection object never retains -ClientId,
        -Issuer, -KeyId, or -PrivateKeyFile, so there is nothing to reconnect with once
        the OAuth2 access token expires. The call simply fails.

        How long that takes depends entirely on the API client's configuration on the
        array (access_token_ttl_in_ms), not on this module — it can be set anywhere from
        1 second to 24 hours (server default: 24 hours) and this cmdlet has no visibility
        into that value at connect time. On a long-lived API client this rarely matters
        in practice; on one deliberately configured with a short TTL for tighter
        credential rotation, a Certificate-authenticated session can stop working after
        only seconds with no automatic recovery.

        Workarounds: re-run Connect-PfbArray to obtain a fresh access token, or prefer
        -ApiToken for long-running sessions/automation against an array with a
        short-TTL API client.
    .EXAMPLE
        $array = Connect-PfbArray -Endpoint fb01.example.com -ApiToken $token -IgnoreCertificateError

        Connect using an API token with SSL bypass for lab environments.
    .EXAMPLE
        $pw = ConvertTo-SecureString "MyPassword" -AsPlainText -Force
        $array = Connect-PfbArray -Endpoint fb01.example.com -Username "pureuser" -Password $pw -IgnoreCertificateError

        Connect using username and password via the native REST 2.x /api/login endpoint.
    .EXAMPLE
        $cred = Get-Credential
        $array = Connect-PfbArray -Endpoint fb01.example.com -Credential $cred -IgnoreCertificateError

        Connect using a PSCredential object.
    .EXAMPLE
        $array = Connect-PfbArray -Endpoint fb01.example.com -Username "pureuser" `
            -ClientId "9472190-f792-712e-a639-0839fa830922" `
            -Issuer "myapp" -KeyId "e50c1a8f-..." `
            -PrivateKeyFile "C:\keys\fb-private.pem" -IgnoreCertificateError

        Connect using OAuth2 JWT certificate-based authentication.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ApiToken')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Endpoint,

        [Parameter(Mandatory, ParameterSetName = 'ApiToken', Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$ApiToken,

        [Parameter(ParameterSetName = 'Credential')]
        [Parameter(Mandatory, ParameterSetName = 'Certificate')]
        [ValidateNotNullOrEmpty()]
        [string]$Username,

        [Parameter(Mandatory, ParameterSetName = 'Credential')]
        [System.Security.SecureString]$Password,

        [Parameter(ParameterSetName = 'Credential')]
        [Parameter(Mandatory, ParameterSetName = 'PSCredential')]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(Mandatory, ParameterSetName = 'Certificate')]
        [string]$ClientId,

        [Parameter(Mandatory, ParameterSetName = 'Certificate')]
        [string]$Issuer,

        [Parameter(Mandatory, ParameterSetName = 'Certificate')]
        [string]$KeyId,

        [Parameter(Mandatory, ParameterSetName = 'Certificate')]
        [string]$PrivateKeyFile,

        [Parameter(ParameterSetName = 'Certificate')]
        [System.Security.SecureString]$PrivateKeyPassword,

        [Parameter()]
        [string]$ApiVersion,

        [Parameter()]
        [switch]$IgnoreCertificateError,

        [Parameter()]
        [int]$HttpTimeout = 30000
    )

    # Handle SSL bypass
    if ($IgnoreCertificateError) {
        Set-PfbCertificatePolicy
    }

    # Resolve PSCredential to username/password
    if ($PSCmdlet.ParameterSetName -eq 'PSCredential') {
        $Username = $Credential.UserName
        $Password = $Credential.Password
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'Credential' -and $Credential) {
        # Credential set allows optional -Credential alongside -Password
        if (-not $Username) { $Username = $Credential.UserName }
        if (-not $Password) { $Password = $Credential.Password }
    }

    # Discover supported API versions
    $versionUri = "https://${Endpoint}/api/api_version"
    $versionParams = @{
        Method = 'GET'
        Uri    = $versionUri
    }
    if ($IgnoreCertificateError -and $PSVersionTable.PSVersion.Major -ge 6) {
        $versionParams['SkipCertificateCheck'] = $true
    }

    try {
        $versionResponse = Invoke-RestMethod @versionParams -ErrorAction Stop
    }
    catch {
        throw "Failed to connect to FlashBlade at '${Endpoint}': $($_.Exception.Message)"
    }

    $supportedVersions = $versionResponse.versions

    # Negotiate API version
    if ($ApiVersion) {
        if ($ApiVersion -notin $supportedVersions) {
            throw "API version '${ApiVersion}' is not supported by this FlashBlade. Supported versions: $($supportedVersions -join ', ')"
        }
        $negotiatedVersion = $ApiVersion
    }
    else {
        # Pick the highest 2.x version
        $v2Versions = $supportedVersions | Where-Object { $_ -match '^2\.' } | ForEach-Object {
            $parts = $_ -split '\.'
            [PSCustomObject]@{
                Version = $_
                Major   = [int]$parts[0]
                Minor   = [int]$parts[1]
            }
        } | Sort-Object Major, Minor -Descending

        if (-not $v2Versions) {
            throw "No REST API 2.x versions supported by this FlashBlade. Supported: $($supportedVersions -join ', ')"
        }

        $negotiatedVersion = $v2Versions[0].Version
    }

    # Authenticate based on method
    $authToken = $null
    $bearerToken = $null

    if ($PSCmdlet.ParameterSetName -eq 'ApiToken') {
        # Direct API token login
        $loginUri = "https://${Endpoint}/api/login"
        $loginHeaders = @{ 'api-token' = $ApiToken }
        $loginParams = @{
            Method  = 'POST'
            Uri     = $loginUri
            Headers = $loginHeaders
        }
        if ($IgnoreCertificateError -and $PSVersionTable.PSVersion.Major -ge 6) {
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
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'Certificate') {
        # OAuth2 JWT certificate-based authentication
        # Step 1: Generate a signed JWT
        $jwtParams = @{
            KeyId       = $KeyId
            ClientId    = $ClientId
            Issuer      = $Issuer
            Username    = $Username
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

        # Step 2: Exchange JWT for OAuth2 access token
        $oauthBody = "grant_type=urn:ietf:params:oauth:grant-type:token-exchange&subject_token=${jwt}&subject_token_type=urn:ietf:params:oauth:token-type:jwt"
        $oauthParams = @{
            Method      = 'POST'
            Uri         = "https://${Endpoint}/oauth2/1.0/token"
            Body        = $oauthBody
            ContentType = 'application/x-www-form-urlencoded'
        }
        if ($IgnoreCertificateError -and $PSVersionTable.PSVersion.Major -ge 6) {
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

        # The bearer token IS the auth token for REST API calls
        # It goes in the Authorization header, not x-auth-token
        $authToken = $bearerToken
        $ApiToken = $null  # No API token in Certificate flow
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'Credential' -or $PSCmdlet.ParameterSetName -eq 'PSCredential') {
        # Native REST 2.x username/password login — POST /api/login with JSON body.
        # /api/login is unversioned and is part of REST 2.x. No SSH required.
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
        try {
            $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
            $loginBody = @{ username = $Username; password = $plainPassword } | ConvertTo-Json -Compress
        }
        finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) | Out-Null
            $plainPassword = $null
        }

        $loginParams = @{
            Method      = 'POST'
            Uri         = "https://${Endpoint}/api/login"
            Body        = $loginBody
            ContentType = 'application/json'
        }
        if ($IgnoreCertificateError -and $PSVersionTable.PSVersion.Major -ge 6) {
            $loginParams['SkipCertificateCheck'] = $true
        }
        $loginBody = $null  # release the JSON body containing the password

        try {
            $loginResponse = Invoke-WebRequest @loginParams -UseBasicParsing -ErrorAction Stop
        }
        catch {
            $detail = if ($_.ErrorDetails.Message) { " ($($_.ErrorDetails.Message))" } else { '' }
            throw "Username/password authentication failed for FlashBlade '${Endpoint}': $($_.Exception.Message)${detail}"
        }

        $authToken = $loginResponse.Headers['x-auth-token']
        if ($authToken -is [array]) { $authToken = $authToken[0] }

        # Try to retrieve (or mint) a long-lived API token for auto-reconnect.
        # Best-effort: succeeds for users with admin privileges; falls through silently otherwise.
        # Use a local variable since the $ApiToken parameter retains its [ValidateNotNullOrEmpty]
        # constraint and would reject a $null reassignment.
        $cachedApiToken  = $null
        $tokenHeaders    = @{ 'x-auth-token' = $authToken }
        $encodedName     = [System.Uri]::EscapeDataString($Username)
        $tokenBaseUri    = "https://${Endpoint}/api/${negotiatedVersion}/admins/api-tokens"
        $tokenInvokeArgs = @{}
        if ($IgnoreCertificateError -and $PSVersionTable.PSVersion.Major -ge 6) {
            $tokenInvokeArgs['SkipCertificateCheck'] = $true
        }
        # Pick the item whose admin matches our username. The /admins/api-tokens endpoint
        # silently ignores the names= / ids= filters and returns all admins, with the
        # caller's own token unmasked and other admins' tokens redacted to '****'. We must
        # filter client-side to avoid grabbing a peer admin's masked entry.
        $isOurAdmin = { param($item) $item.admin -and $item.admin.name -eq $Username }
        $isRealToken = { param($t) $t -and $t -ne '****' -and -not ($t -match '^\*+$') }

        try {
            $existing = Invoke-RestMethod -Uri "${tokenBaseUri}?expose_api_token=true" `
                                          -Headers $tokenHeaders -ErrorAction Stop @tokenInvokeArgs
            $mine = $existing.items | Where-Object { & $isOurAdmin $_ } | Select-Object -First 1
            if ($mine -and $mine.api_token -and (& $isRealToken $mine.api_token.token)) {
                $cachedApiToken = $mine.api_token.token
            }
        }
        catch {
            Write-Verbose "Could not read existing API token for '$Username': $($_.Exception.Message)"
        }
        if (-not $cachedApiToken) {
            try {
                $minted = Invoke-RestMethod -Uri "${tokenBaseUri}?names=${encodedName}" `
                                            -Method POST -Headers $tokenHeaders -ErrorAction Stop @tokenInvokeArgs
                $mine = $minted.items | Where-Object { & $isOurAdmin $_ } | Select-Object -First 1
                if ($mine -and $mine.api_token -and (& $isRealToken $mine.api_token.token)) {
                    $cachedApiToken = $mine.api_token.token
                }
            }
            catch {
                Write-Verbose "Could not mint API token for '$Username': $($_.Exception.Message)"
            }
        }
        if ($cachedApiToken) {
            $ApiToken = $cachedApiToken
        } else {
            Write-Verbose "Connected without a cached API token. Auto-reconnect on 401 will be unavailable for this session."
        }
    }

    if ([string]::IsNullOrEmpty($authToken)) {
        throw "Authentication failed: No x-auth-token received from FlashBlade '${Endpoint}'."
    }

    # Build connection object — properties align with PureRestClientBase (Pfa2)
    $connection = [PSCustomObject]@{
        PSTypeName           = 'PureStorage.FlashBlade.Connection'
        # Pfa2-aligned properties
        HttpEndpoint         = "https://${Endpoint}"
        Username             = $Username
        ApiToken             = $ApiToken
        RestApiVersion       = $negotiatedVersion
        # Internal properties used by Invoke-PfbApiRequest / Disconnect-PfbArray
        Endpoint             = $Endpoint
        AuthToken            = $authToken
        ApiVersion           = $negotiatedVersion
        BearerToken          = $bearerToken
        AuthMethod           = $PSCmdlet.ParameterSetName
        SkipCertificateCheck = [bool]$IgnoreCertificateError
        HttpTimeoutMs        = $HttpTimeout
        ConnectedAt          = [datetime]::UtcNow
    }

    # Hide secrets from default display. Sensitive fields (ApiToken, AuthToken,
    # BearerToken) are still accessible programmatically — Format-List * / direct
    # property access ($conn.ApiToken) work — but they no longer appear in the
    # default Format-List view that runs when a user just types $conn at the prompt.
    $defaultProps = @(
        'HttpEndpoint', 'Endpoint', 'Username', 'AuthMethod',
        'ApiVersion', 'RestApiVersion', 'SkipCertificateCheck', 'ConnectedAt'
    )
    $psStandardMembers = [System.Management.Automation.PSMemberInfo[]]@(
        [System.Management.Automation.PSPropertySet]::new('DefaultDisplayPropertySet', [string[]]$defaultProps)
    )
    Add-Member -InputObject $connection -MemberType MemberSet -Name PSStandardMembers -Value $psStandardMembers

    # Cache the connection
    $script:PfbDefaultArray = $connection
    $script:PfbArrays[$Endpoint] = $connection

    return $connection
}
