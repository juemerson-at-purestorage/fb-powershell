<#
.SYNOPSIS
    Category 1 (uncovered endpoints) and category 2 (parameter gaps) of the API drift
    report. Dot-sourced by tools/Build-PfbApiDriftReport.ps1 and its Pester tests.
    Category 3 (ValidateSet drift) lives here too -- see Get-PfbValidateSetDrift, added
    in a later task -- reusing Resolve-PfbFieldValueEnum from
    tools/lib/PfbValueEnumTools.ps1. Category 4 (new ValidateSet candidates) needs no new
    code at all: it's tools/Build-PfbFieldCmdletMap.ps1's existing 'matched' output,
    consumed directly by the orchestrator.
#>

# Deliberately NOT Set-StrictMode -- same reasoning as PfbSpecTools.ps1/PfbValueEnumTools.ps1.

# Endpoints reached exclusively through hand-written auth code that never calls
# Invoke-PfbApiRequest (it's what establishes the session Invoke-PfbApiRequest itself
# depends on) -- confirmed by reading Public/Connection/Connect-PfbArray.ps1,
# Public/Connection/Disconnect-PfbArray.ps1, and Private/Invoke-PfbOAuth2Login.ps1
# directly. admins/api-tokens is deliberately NOT here: Connect-PfbArray.ps1 also touches
# it via raw Invoke-RestMethod for post-login token minting, but GET/POST/DELETE
# admins/api-tokens are already covered through the standard Invoke-PfbApiRequest
# convention by Public/Admin/{Get,New,Remove}-PfbApiToken.ps1, so Get-PfbModuleCalledEndpoints's
# normal scan already sees them without needing this allowlist.
$script:PfbBespokeAuthEndpoints = @(
    'GET /api/api_version',
    'POST /api/login',
    'POST /api/logout',
    'POST /oauth2/1.0/token'
)

function Get-PfbModuleCalledEndpoints {
    <#
    .SYNOPSIS
        Scans every Public/*.ps1 and Private/*.ps1 function for Invoke-PfbApiRequest
        calls, extracting each literal -Method/-Endpoint pair, normalized to the same
        "<METHOD> /<endpoint>" key format Data/PfbCapabilityMap.json uses (see
        Private/Assert-PfbApiCapability.ps1:40-41).
    .OUTPUTS
        [PSCustomObject]@{ Key; Method; Endpoint; Resolved; Cmdlet; File }[] -- Resolved
        is $false (Key/Method/Endpoint all $null) when a call's -Endpoint isn't a plain
        string literal (built dynamically via interpolation or a variable), never
        silently dropped or guessed at.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$PublicDirectory,
        [Parameter(Mandatory)] [string]$PrivateDirectory
    )

    $results = [System.Collections.Generic.List[object]]::new()
    $files = @(Get-ChildItem -Path $PublicDirectory -Filter '*.ps1' -Recurse -File) +
             @(Get-ChildItem -Path $PrivateDirectory -Filter '*.ps1' -Recurse -File)

    foreach ($file in $files) {
        $tokens = $null; $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
        $functionAsts = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)

        foreach ($funcAst in $functionAsts) {
            $commands = $funcAst.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.CommandAst] -and
                $n.GetCommandName() -eq 'Invoke-PfbApiRequest'
            }, $true)

            foreach ($cmd in $commands) {
                $method = $null; $endpoint = $null
                $elements = $cmd.CommandElements
                for ($i = 0; $i -lt $elements.Count; $i++) {
                    $el = $elements[$i]
                    if ($el -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
                    $next = if ($i + 1 -lt $elements.Count) { $elements[$i + 1] } else { $null }
                    if (-not $next) { continue }
                    if ($el.ParameterName -eq 'Method' -and $next -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                        $method = $next.Value
                    }
                    elseif ($el.ParameterName -eq 'Endpoint' -and $next -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                        $endpoint = $next.Value
                    }
                }

                if ($method -and $endpoint) {
                    $normalizedEndpoint = '/' + $endpoint.TrimStart('/')
                    $results.Add([PSCustomObject]@{
                        Key      = "$($method.ToUpperInvariant()) $normalizedEndpoint"
                        Method   = $method.ToUpperInvariant()
                        Endpoint = $normalizedEndpoint
                        Resolved = $true
                        Cmdlet   = $funcAst.Name
                        File     = $file.FullName
                    })
                }
                else {
                    $results.Add([PSCustomObject]@{
                        Key      = $null
                        Method   = $null
                        Endpoint = $null
                        Resolved = $false
                        Cmdlet   = $funcAst.Name
                        File     = $file.FullName
                    })
                }
            }
        }
    }

    return $results
}

function Get-PfbEndpointCoverageGaps {
    <#
    .SYNOPSIS
        Category 1: every Data/PfbCapabilityMap.json endpoint key that no
        Get-PfbModuleCalledEndpoints result covers and that isn't on -BespokeAllowlist.
    .OUTPUTS
        [PSCustomObject]@{ Endpoint; MinVersion }[]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $CapabilityMap,
        [Parameter(Mandatory)] [object[]]$CalledEndpoints,
        [string[]]$BespokeAllowlist = @()
    )

    $calledKeys = [System.Collections.Generic.HashSet[string]]::new([string[]]@(
        $CalledEndpoints | Where-Object { $_.Resolved } | ForEach-Object { $_.Key }
    ))

    foreach ($key in $CapabilityMap.endpoints.PSObject.Properties.Name) {
        if ($calledKeys.Contains($key)) { continue }
        if ($BespokeAllowlist -contains $key) { continue }
        [PSCustomObject]@{
            Endpoint   = $key
            MinVersion = $CapabilityMap.endpoints.$key.minVersion
        }
    }
}
