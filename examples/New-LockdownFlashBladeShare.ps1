<#
.SYNOPSIS
    Creates a FlashBlade SMB file share locked down to the provisioning script's identity,
    applies NTFS ACLs, then flips the share policy to the production policy.

    === DEMO / SAMPLE SCRIPT - PROVIDED AS-IS ===

    This script is a REFERENCE IMPLEMENTATION provided for evaluation and as a
    starting point for customer deployments. It is NOT a supported Everpure
    product, is shipped without warranty of any kind (express or implied), and
    no Everpure entity is responsible for any outcome from its use.

    Before running this script in any environment, the customer is responsible for:
      - Reviewing the source code in full
      - Testing in a non-production environment first
      - Adapting parameters, error handling, retry logic, and logging to local
        operational standards and change-control processes
      - Verifying that the lockdown principal, NTFS ACEs, and production share
        policy match the customer's security requirements
      - All operational consequences of executing it, including (but not limited
        to) file-system creation, policy mutation, and ACL application

    Use at your own risk.

.DESCRIPTION
    Reference implementation of the three-phase secure SMB share-creation pattern:

      1. Create the file share locked down to the provisioning identity (no public access)
      2. Modify NTFS permissions to the desired layout (via Windows icacls)
      3. Flip the SMB share policy to the production policy that opens up access

    Step (1) keeps the share inaccessible to anyone except $LockdownPrincipal for the
    duration of step (2), eliminating the brief "wide-open" window the FlashBlade's
    default share policy would otherwise create.

    The script is idempotent: re-running it against an existing share with the same
    -Name fails with a clear error rather than silently re-creating or mutating data.
    Wildcard names ('*') are rejected at parameter binding.

    REQUIREMENTS:
      - PureStorageFlashBladePowerShell module v2.0.1 or later
      - Windows host with icacls.exe (every Windows install)
      - Network reachability to the FlashBlade data VIP (for the NTFS step)
      - $LockdownPrincipal must be a real identity the FlashBlade can authenticate
        (AD-joined, LDAP, or `Everyone` for lab tests). The script's runtime identity
        must be authorized to write to the share via that principal.

.PARAMETER Endpoint
    FlashBlade hostname or IP.

.PARAMETER Credential
    PSCredential for FlashBlade login.

.PARAMETER Name
    File system name. The SMB share will be `\\<data-vip>\<Name>`.

.PARAMETER ProvisionedGB
    Quota in GB. The script enforces it as a hard limit.

.PARAMETER LockdownSharePolicyName
    Name of the lockdown SMB share policy. Created if missing. Default: `fb-script-lockdown`.

.PARAMETER LockdownPrincipal
    Identity that gets `full_control` during step (1). Should be the script's runtime
    identity (e.g. `CORP\svc-fb-prov`). Use `Everyone` only for lab tests.

.PARAMETER ProductionSharePolicyName
    Name of the production SMB share policy that gets attached in step (3). MUST already
    exist on the FlashBlade - the script does not create it.

.PARAMETER NtfsAclEntries
    Array of hashtables describing NTFS ACEs to apply in step (2). Each entry takes:
      @{ Identity = 'CORP\group'; Rights = 'Modify' | 'FullControl' | 'ReadAndExecute';
         Inheritance = 'ContainerInherit, ObjectInherit'; AccessControlType = 'Allow' | 'Deny' }
    If omitted, step (2) is skipped (useful for lab smoke tests).

.PARAMETER DataVip
    Override for the FB data VIP. By default the script picks the first enabled `data`
    network interface returned by Get-PfbNetworkInterface.

.PARAMETER IgnoreCertificateError
    Bypass SSL cert validation on the FlashBlade. Standard for labs.

.PARAMETER UncMountTimeoutSec
    Seconds to wait for the SMB share to be reachable over the network before failing
    step (2). Default 60.

.EXAMPLE
    $cred = Get-Credential pureuser
    .\New-LockdownFlashBladeShare.ps1 `
        -Endpoint fb01.corp.example.com `
        -Credential $cred `
        -Name proj-quartz `
        -ProvisionedGB 500 `
        -LockdownPrincipal 'CORP\svc-fb-prov' `
        -ProductionSharePolicyName 'corp-readwrite-eng' `
        -NtfsAclEntries @(
            @{ Identity = 'CORP\quartz-rw';  Rights = 'Modify';       Inheritance = 'ContainerInherit, ObjectInherit'; AccessControlType = 'Allow' },
            @{ Identity = 'CORP\quartz-ro';  Rights = 'ReadAndExecute'; Inheritance = 'ContainerInherit, ObjectInherit'; AccessControlType = 'Allow' }
        ) `
        -IgnoreCertificateError

.NOTES
    See Tests/SMB_SHARE_WORKFLOW.md for the per-operation cmdlet mapping and gotchas.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Endpoint,

    [Parameter(Mandatory)]
    [System.Management.Automation.PSCredential]$Credential,

    [Parameter(Mandatory)]
    [ValidateScript({
        if ($_ -match '[\*\?%]') { throw "Name '$_' contains wildcard characters." }
        if ([string]::IsNullOrWhiteSpace($_)) { throw "Name cannot be empty." }
        $true
    })]
    [string]$Name,

    [Parameter(Mandatory)]
    [ValidateRange(1, 1048576)]
    [int]$ProvisionedGB,

    [Parameter()]
    [string]$LockdownSharePolicyName = 'fb-script-lockdown',

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$LockdownPrincipal,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ProductionSharePolicyName,

    [Parameter()]
    [hashtable[]]$NtfsAclEntries,

    [Parameter()]
    [string]$DataVip,

    [Parameter()]
    [switch]$IgnoreCertificateError,

    [Parameter()]
    [int]$UncMountTimeoutSec = 60
)

$ErrorActionPreference = 'Stop'

$modName = 'PureStorageFlashBladePowerShell'
if (-not (Get-Module $modName)) {
    Import-Module $modName -MinimumVersion 2.0.1 -ErrorAction Stop
}

$rightsToIcacls = @{
    'Read'             = '(R)'
    'ReadAndExecute'   = '(RX)'
    'Modify'           = '(M)'
    'Write'            = '(W)'
    'FullControl'      = '(F)'
}
$inheritToIcacls = @{
    ''                                                = ''
    'None'                                            = ''
    'ContainerInherit'                                = '(CI)'
    'ObjectInherit'                                   = '(OI)'
    'ContainerInherit, ObjectInherit'                 = '(OI)(CI)'
    'ObjectInherit, ContainerInherit'                 = '(OI)(CI)'
}

function Write-Step {
    param([string]$Message)
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor Cyan
}

Write-Step "Connecting to FlashBlade $Endpoint..."
$connectParams = @{ Endpoint = $Endpoint; Credential = $Credential }
if ($IgnoreCertificateError) { $connectParams['IgnoreCertificateError'] = $true }
$fb = Connect-PfbArray @connectParams
Write-Step "  Connected. ApiVersion=$($fb.ApiVersion); AuthMethod=$($fb.AuthMethod)."

try {
    $existing = Get-PfbFileSystem -Array $fb -Filter "name='$Name'" -ErrorAction SilentlyContinue
    if (@($existing | Where-Object { $_.name -eq $Name }).Count -gt 0) {
        throw "A file system named '$Name' already exists. Refusing to mutate. Remove it first or choose a different -Name."
    }

    $prod = Get-PfbSmbSharePolicy -Array $fb -Filter "name='$ProductionSharePolicyName'" -ErrorAction SilentlyContinue
    if (@($prod | Where-Object { $_.name -eq $ProductionSharePolicyName }).Count -eq 0) {
        throw "Production share policy '$ProductionSharePolicyName' not found. Create it on the FlashBlade first."
    }

    Write-Step "Phase 1/3: ensure lockdown SMB share policy '$LockdownSharePolicyName' exists..."
    $lockdown = Get-PfbSmbSharePolicy -Array $fb -Filter "name='$LockdownSharePolicyName'" -ErrorAction SilentlyContinue
    if (@($lockdown | Where-Object { $_.name -eq $LockdownSharePolicyName }).Count -eq 0) {
        if ($PSCmdlet.ShouldProcess($LockdownSharePolicyName, 'Create lockdown SMB share policy')) {
            New-PfbSmbSharePolicy -Array $fb -Name $LockdownSharePolicyName -ErrorAction Stop | Out-Null
            Write-Step "  Created policy."
        }
    } else {
        Write-Step "  Policy already exists."
    }

    # Compound filters on this endpoint ("policy.name='x' and principal='y'") return a
    # count-only stub. Filter by policy name only (works) then narrow client-side.
    $existingRules = @(
        Get-PfbSmbShareRule -Array $fb -Filter "policy.name='$LockdownSharePolicyName'" -ErrorAction SilentlyContinue |
            Where-Object { $_.principal -eq $LockdownPrincipal }
    )
    if ($existingRules.Count -eq 0) {
        if ($PSCmdlet.ShouldProcess("$LockdownSharePolicyName/$LockdownPrincipal", 'Add full_control rule')) {
            New-PfbSmbShareRule -Array $fb -PolicyName $LockdownSharePolicyName `
                -Attributes @{ principal = $LockdownPrincipal; full_control = 'allow' } `
                -ErrorAction Stop | Out-Null
            Write-Step "  Added rule: $LockdownPrincipal -> full_control."
        }
    } else {
        Write-Step "  Rule for $LockdownPrincipal already present."
    }

    Write-Step "Phase 2/3: creating file system '$Name' with lockdown policy attached..."
    $bytes = [int64]$ProvisionedGB * 1GB
    if ($PSCmdlet.ShouldProcess($Name, "Create file system ($ProvisionedGB GB, SMB+$LockdownSharePolicyName)")) {
        New-PfbFileSystem -Array $fb -Name $Name `
            -Provisioned $bytes -HardLimit `
            -Smb -SmbSharePolicy $LockdownSharePolicyName `
            -ErrorAction Stop | Out-Null
    }
    Write-Step "  Created. Share is currently locked down: only '$LockdownPrincipal' has access."

    if (-not $NtfsAclEntries -or $NtfsAclEntries.Count -eq 0) {
        Write-Step "  No -NtfsAclEntries supplied; skipping the NTFS step."
    } else {
        if (-not $DataVip) {
            $dataNi = Get-PfbNetworkInterface -Array $fb |
                Where-Object { $_.services -contains 'data' -and $_.enabled } |
                Sort-Object name | Select-Object -First 1
            if (-not $dataNi) { throw "No enabled 'data' network interface found and -DataVip not provided." }
            $DataVip = $dataNi.address
            Write-Step "  Resolved data VIP: $DataVip (from $($dataNi.name))"
        }
        $unc = "\\$DataVip\$Name"

        Write-Step "  Waiting for SMB share at $unc to be reachable (timeout ${UncMountTimeoutSec}s)..."
        $deadline = (Get-Date).AddSeconds($UncMountTimeoutSec)
        $reachable = $false
        while ((Get-Date) -lt $deadline) {
            try { if (Test-Path -LiteralPath $unc -ErrorAction Stop) { $reachable = $true; break } } catch { }
            Start-Sleep -Seconds 2
        }
        if (-not $reachable) {
            throw "SMB share $unc did not become reachable within ${UncMountTimeoutSec}s. " +
                  "Confirm: (a) the data VIP is correct; (b) the script's identity matches '$LockdownPrincipal' and is permitted by the lockdown policy."
        }
        Write-Step "  Share reachable."

        Write-Step "  Applying $($NtfsAclEntries.Count) NTFS ACE(s) via icacls..."
        foreach ($ace in $NtfsAclEntries) {
            foreach ($k in 'Identity','Rights') {
                if (-not $ace.ContainsKey($k)) { throw "NTFS ACL entry missing required key '$k'." }
            }
            $ic = $rightsToIcacls[$ace.Rights]
            if (-not $ic) { throw "Unknown Rights value '$($ace.Rights)'. Use Read, ReadAndExecute, Modify, Write, FullControl." }
            $inh = ''
            if ($ace.ContainsKey('Inheritance')) { $inh = $inheritToIcacls[$ace.Inheritance] }
            $type = if ($ace.ContainsKey('AccessControlType')) { $ace.AccessControlType } else { 'Allow' }
            $flag = if ($type -eq 'Deny') { '/deny' } else { '/grant' }

            $grantStr = "$($ace.Identity):$inh$ic"
            if ($PSCmdlet.ShouldProcess("$unc -> $($ace.Identity)", "icacls $flag $grantStr")) {
                & icacls.exe $unc $flag $grantStr | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    throw "icacls failed (exit $LASTEXITCODE) granting $($ace.Identity) -> $($ace.Rights) on $unc."
                }
                Write-Step "    granted: $($ace.Identity) -> $($ace.Rights) ($flag $grantStr)"
            }
        }
    }

    Write-Step "Phase 3/3: flipping share policy from '$LockdownSharePolicyName' to '$ProductionSharePolicyName'..."
    if ($PSCmdlet.ShouldProcess($Name, "Attach production SMB share policy '$ProductionSharePolicyName'")) {
        Update-PfbFileSystem -Array $fb -Name $Name -SmbSharePolicy $ProductionSharePolicyName -ErrorAction Stop | Out-Null
    }
    Write-Step "  Flipped."

    $fs = Get-PfbFileSystem -Array $fb -Name $Name
    $attachedPolicy = $fs.smb.share_policy.name
    if ($attachedPolicy -ne $ProductionSharePolicyName) {
        throw "Post-flip verification FAILED: attached share policy is '$attachedPolicy', expected '$ProductionSharePolicyName'."
    }
    Write-Step "  Verified: file system '$Name' is now attached to share policy '$ProductionSharePolicyName'."

    [pscustomobject]@{
        Name              = $Name
        Endpoint          = $Endpoint
        ProvisionedGB     = $ProvisionedGB
        UncPath           = if ($DataVip) { "\\$DataVip\$Name" } else { $null }
        LockdownPolicy    = $LockdownSharePolicyName
        ProductionPolicy  = $ProductionSharePolicyName
        NtfsEntries       = @($NtfsAclEntries).Count
        Result            = 'Success'
    }
}
finally {
    if ($fb) {
        Disconnect-PfbArray -Array $fb -ErrorAction SilentlyContinue | Out-Null
    }
}
