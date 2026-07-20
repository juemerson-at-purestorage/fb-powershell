<#
.SYNOPSIS
    Maps external directory (e.g. Active Directory) users into a FlashBlade local
    directory-services group, the supported path for granting AD users NTFS access
    to SMB shares.

.DESCRIPTION
    Answers a common question: "How do I use the API to add external users to a
    local directory-services group?"

    On FlashBlade the flow is three objects, all under 'directory-services/local':

        local directory service  ->  local group  ->  group member(s)

    1. A local directory service is the on-array user/group database.
    2. A local group lives under that service and is what you grant NTFS rights to.
    3. Members are added to the group. Members MAY be external AD accounts - that is
       exactly how you give an AD user (or AD group) access via a local group.

    This script is idempotent: it creates the directory service and group only if
    they are missing, then adds the requested members. It is a DEMO/SAMPLE - review
    it, run it against a non-production array first, and adapt it to your environment.

.PARAMETER Endpoint
    FlashBlade management endpoint (FQDN or IP).

.PARAMETER Credential
    Credential used to connect. Omit to reuse an existing default connection.

.PARAMETER DirectoryService
    Name of the local directory service (created if absent). Example: "mydomain".

.PARAMETER Group
    Name of the local group (created if absent). Example: "mydomain\share-admins".

.PARAMETER Member
    One or more external member names to add. Use the fully-qualified form the array
    expects, e.g. "CORP\jdoe" or "jdoe@corp.example.com".

.EXAMPLE
    .\Add-ExternalUsersToLocalGroup.ps1 -Endpoint fb01.example.com -Credential (Get-Credential) `
        -DirectoryService mydomain -Group 'mydomain\share-admins' -Member 'CORP\jdoe','CORP\asmith'

    Ensures the "mydomain" local directory service and "mydomain\share-admins" group
    exist, then adds two external AD users to the group.

.NOTES
    Cmdlets used (all shipped with the module):
      New-PfbLocalDirectoryService / Get-PfbLocalDirectoryService
      New-PfbLocalGroup            / Get-PfbLocalGroup
      New-PfbLocalGroupMember      / Get-PfbLocalGroupMember
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter()] [string]$Endpoint,
    [Parameter()] [pscredential]$Credential,
    [Parameter(Mandatory)] [string]$DirectoryService,
    [Parameter(Mandatory)] [string]$Group,
    [Parameter(Mandatory)] [string[]]$Member
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module PureStorageFlashBladePowerShell -ErrorAction Stop

# --- Connect (or reuse the default connection) ---------------------------------
$fb = $null
if ($Endpoint) {
    $connectArgs = @{ Endpoint = $Endpoint }
    if ($Credential) { $connectArgs['Credential'] = $Credential }
    $fb = Connect-PfbArray @connectArgs
}
# When $fb is $null the cmdlets fall back to the module's default connection.
$arrayArg = if ($fb) { @{ Array = $fb } } else { @{} }

# --- 1. Ensure the local directory service exists ------------------------------
$existingDs = Get-PfbLocalDirectoryService @arrayArg |
    Where-Object { $_.name -eq $DirectoryService }
if (-not $existingDs) {
    Write-Verbose "Creating local directory service '$DirectoryService'."
    New-PfbLocalDirectoryService -Name $DirectoryService @arrayArg | Out-Null
} else {
    Write-Verbose "Local directory service '$DirectoryService' already exists."
}

# --- 2. Ensure the local group exists ------------------------------------------
$existingGroup = Get-PfbLocalGroup @arrayArg | Where-Object { $_.name -eq $Group }
if (-not $existingGroup) {
    Write-Verbose "Creating local group '$Group'."
    New-PfbLocalGroup -Name $Group @arrayArg | Out-Null
} else {
    Write-Verbose "Local group '$Group' already exists."
}

# --- 3. Add the external members, skipping any already present -----------------
$current = @(Get-PfbLocalGroupMember -Group $Group @arrayArg | ForEach-Object { $_.member.name })
$toAdd   = @($Member | Where-Object { $_ -notin $current })

if ($toAdd.Count -eq 0) {
    Write-Host "All requested members are already in '$Group'. Nothing to do."
} else {
    Write-Verbose "Adding $($toAdd.Count) member(s) to '$Group': $($toAdd -join ', ')"
    New-PfbLocalGroupMember -Group $Group -Member $toAdd @arrayArg | Out-Null
}

# --- 4. Show the resulting membership ------------------------------------------
Get-PfbLocalGroupMember -Group $Group @arrayArg
