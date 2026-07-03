function Remove-PfbObjectStoreUserAccessPolicy {
    <#
    .SYNOPSIS
        Removes the link between an object store user and an access policy.
    .DESCRIPTION
        Deletes the association between an object store user and an access
        policy. Accepts flattened association objects from
        Get-PfbObjectStoreUserAccessPolicy on the pipeline.
    .PARAMETER MemberName
        The name of the object store user (account/user format). Binds from pipeline property 'MemberName'.
    .PARAMETER PolicyName
        The name of the access policy to unlink. Binds from pipeline property 'PolicyName'.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Remove-PfbObjectStoreUserAccessPolicy -MemberName "acct1/user1" -PolicyName "full-access-policy"
        Removes the link between the user and the access policy.
    .EXAMPLE
        Get-PfbObjectStoreUserAccessPolicy -MemberName "acct1/old-user" | Remove-PfbObjectStoreUserAccessPolicy
        Removes all access policy links from a user.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
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

        if ($PSCmdlet.ShouldProcess("User=$MemberName, Policy=$PolicyName", 'Remove user access policy link')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'object-store-users/object-store-access-policies' -QueryParams $queryParams
        }
    }
}
