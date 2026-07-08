function New-PfbObjectStoreUserAccessPolicy {
    <#
    .SYNOPSIS
        Links an access policy to an object store user.
    .DESCRIPTION
        Creates an association between an object store user and an access
        policy. Once linked, the user inherits the permissions defined by
        the access policy. Accepts flattened association objects from
        Get-PfbObjectStoreUserAccessPolicy on the pipeline.
    .PARAMETER MemberName
        The name of the object store user (account/user format). Binds from pipeline property 'MemberName'.
    .PARAMETER PolicyName
        The name of the access policy to link. Binds from pipeline property 'PolicyName'.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        New-PfbObjectStoreUserAccessPolicy -MemberName "acct1/user1" -PolicyName "full-access-policy"
        Links the full-access-policy to the specified user.
    .EXAMPLE
        Get-PfbObjectStoreUserAccessPolicy -MemberName "acct1/user1" | New-PfbObjectStoreUserAccessPolicy -PolicyName "another-policy"
        Adds another policy link for the user.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [string]$MemberName,

        [Parameter(Mandatory, Position = 1, ValueFromPipelineByPropertyName)]
        [string]$PolicyName,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{
            'member_names' = $MemberName
            'policy_names' = $PolicyName
        }

        if ($PSCmdlet.ShouldProcess("User=$MemberName, Policy=$PolicyName", 'Create user access policy link')) {
            Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'object-store-users/object-store-access-policies' -QueryParams $queryParams
        }
    }
}
