function New-PfbObjectStoreAccessPolicyUser {
    <#
    .SYNOPSIS
        Links an object store user to an access policy.
    .DESCRIPTION
        Creates an association between an object store access policy and an
        object store user. Once linked, the user inherits the permissions
        defined by the access policy. Accepts flattened association objects from
        Get-PfbObjectStoreAccessPolicyUser on the pipeline.
    .PARAMETER PolicyName
        The name of the access policy. Binds from pipeline property 'PolicyName'.
    .PARAMETER MemberName
        The name of the object store user to link (account/user format). Binds from pipeline property 'MemberName'.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        New-PfbObjectStoreAccessPolicyUser -PolicyName "full-access-policy" -MemberName "acct1/user1"
        Links the user to the full-access-policy.
    .EXAMPLE
        Get-PfbObjectStoreAccessPolicyUser -PolicyName "old-policy" | New-PfbObjectStoreAccessPolicyUser -PolicyName "new-policy"
        Re-links every user from old-policy onto new-policy.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [string]$PolicyName,

        [Parameter(Mandatory, Position = 1, ValueFromPipelineByPropertyName)]
        [string]$MemberName,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{
            'policy_names' = $PolicyName
            'member_names' = $MemberName
        }

        if ($PSCmdlet.ShouldProcess("Policy=$PolicyName, User=$MemberName", 'Create access policy user link')) {
            Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'object-store-access-policies/object-store-users' -QueryParams $queryParams
        }
    }
}
