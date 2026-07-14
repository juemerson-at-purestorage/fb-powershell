function Remove-PfbObjectStoreAccessPolicyUser {
    <#
    .SYNOPSIS
        Removes the link between an access policy and an object store user.
    .DESCRIPTION
        Deletes the association between an object store access policy and an
        object store user. Accepts flattened association objects from
        Get-PfbObjectStoreAccessPolicyUser on the pipeline.
    .PARAMETER PolicyName
        The name of the access policy. Binds from pipeline property 'PolicyName'.
    .PARAMETER MemberName
        The name of the object store user to unlink (account/user format). Binds from pipeline property 'MemberName'.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Remove-PfbObjectStoreAccessPolicyUser -PolicyName "full-access-policy" -MemberName "acct1/user1"
        Removes the link between the policy and the user.
    .EXAMPLE
        Get-PfbObjectStoreAccessPolicyUser -PolicyName "old-policy" | Remove-PfbObjectStoreAccessPolicyUser
        Removes all user links from a policy.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
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

        if ($PSCmdlet.ShouldProcess("Policy=$PolicyName, User=$MemberName", 'Remove access policy user link')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'object-store-access-policies/object-store-users' -QueryParams $queryParams
        }
    }
}
