function New-PfbObjectStoreAccessPolicyRole {
    <#
    .SYNOPSIS
        Links an object store role to an access policy.
    .DESCRIPTION
        Creates an association between an object store access policy and an
        object store role. Once linked, the role inherits the permissions
        defined by the access policy. Accepts flattened association objects from
        Get-PfbObjectStoreAccessPolicyRole on the pipeline.
    .PARAMETER PolicyName
        The name of the access policy. Binds from pipeline property 'PolicyName'.
    .PARAMETER MemberName
        The name of the object store role to link. Binds from pipeline property 'MemberName'.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        New-PfbObjectStoreAccessPolicyRole -PolicyName "full-access-policy" -MemberName "s3-admin-role"
        Links the s3-admin-role to the full-access-policy.
    .EXAMPLE
        Get-PfbObjectStoreAccessPolicyRole -PolicyName "old-policy" | New-PfbObjectStoreAccessPolicyRole -PolicyName "new-policy"
        Re-links every role from old-policy onto new-policy.
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

        if ($PSCmdlet.ShouldProcess("Policy=$PolicyName, Role=$MemberName", 'Create access policy role link')) {
            Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'object-store-access-policies/object-store-roles' -QueryParams $queryParams
        }
    }
}
