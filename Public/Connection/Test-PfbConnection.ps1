function Test-PfbConnection {
    <#
    .SYNOPSIS
        Tests connectivity to a Pure Storage FlashBlade array.
    .DESCRIPTION
        The Test-PfbConnection cmdlet verifies that the current connection to a FlashBlade
        is active and the session is valid. Returns $true if connected and authenticated,
        $false otherwise. Useful for scripting to check connection state before running
        operations.
    .PARAMETER Endpoint
        Test connectivity to a specific FlashBlade endpoint. If not specified, tests the
        default connection.
    .PARAMETER Array
        The FlashBlade connection object to test. If not specified, the default connection is used.
    .EXAMPLE
        Test-PfbConnection

        Returns $true if the default FlashBlade connection is active.
    .EXAMPLE
        if (Test-PfbConnection) { Get-PfbArray } else { Write-Warning "Not connected" }

        Checks connectivity before running a command.
    .EXAMPLE
        Test-PfbConnection -Endpoint "fb01.example.com"

        Tests whether a specific FlashBlade endpoint has an active connection.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Position = 0)]
        [string]$Endpoint,

        [Parameter()]
        [PSCustomObject]$Array
    )

    # Check if we have a connection object
    if ($Array) {
        $connection = $Array
    }
    elseif ($Endpoint -and $script:PfbArrays.ContainsKey($Endpoint)) {
        $connection = $script:PfbArrays[$Endpoint]
    }
    elseif ($script:PfbDefaultArray) {
        $connection = $script:PfbDefaultArray
    }
    else {
        return $false
    }

    # Verify the session is still valid by making a lightweight API call
    try {
        $null = Invoke-PfbApiRequest -Array $connection -Method GET -Endpoint 'arrays' -QueryParams @{ limit = 1 }
        return $true
    }
    catch {
        return $false
    }
}
