function Set-PfbTlsProtocol {
    <#
    .SYNOPSIS
        Forces TLS 1.2 for FlashBlade connections on PowerShell 5.1.
    .DESCRIPTION
        PowerShell 5.1 (.NET Framework) does not always default to TLS 1.2, depending on
        OS/registry configuration, and FlashBlade requires TLS 1.2+. This must run
        unconditionally, independent of certificate validation bypass -- forcing a modern
        TLS version and trusting self-signed certificates are unrelated concerns.
    #>
    [CmdletBinding()]
    param()

    if ($PSVersionTable.PSVersion.Major -lt 6) {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    }
    # PowerShell 7+ defaults to TLS 1.2+ already.
}
