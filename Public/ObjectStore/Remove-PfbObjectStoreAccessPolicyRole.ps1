function Remove-PfbObjectStoreAccessPolicyRole {
    <#
    .SYNOPSIS
        Removes the link between an access policy and an object store role.
    .DESCRIPTION
        Deletes the association between an object store access policy and an
        object store role. Accepts flattened association objects from
        Get-PfbObjectStoreAccessPolicyRole on the pipeline.
    .PARAMETER PolicyName
        The name of the access policy. Binds from pipeline property 'PolicyName'.
    .PARAMETER MemberName
        The name of the object store role to unlink. Binds from pipeline property 'MemberName'.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Remove-PfbObjectStoreAccessPolicyRole -PolicyName "full-access-policy" -MemberName "s3-admin-role"
        Removes the link between the policy and the role.
    .EXAMPLE
        Get-PfbObjectStoreAccessPolicyRole -PolicyName "old-policy" | Remove-PfbObjectStoreAccessPolicyRole
        Removes all role links from a policy.
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

        if ($PSCmdlet.ShouldProcess("Policy=$PolicyName, Role=$MemberName", 'Remove access policy role link')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'object-store-access-policies/object-store-roles' -QueryParams $queryParams
        }
    }
}
