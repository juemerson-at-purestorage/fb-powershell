function Test-PfbAlertWatcher {
    <#
    .SYNOPSIS
        Tests an alert watcher configuration on a FlashBlade array.
    .DESCRIPTION
        The Test-PfbAlertWatcher cmdlet tests the connectivity and configuration of an
        alert watcher on the connected Pure Storage FlashBlade.
    .PARAMETER Name
        The name of the alert watcher to test.
    .PARAMETER Id
        The ID of the alert watcher to test.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Test-PfbAlertWatcher -Name "admin@example.com"

        Tests the alert watcher for the specified email address.
    .EXAMPLE
        Test-PfbAlertWatcher -Id "10314f42-020d-7080-8013-000ddt400012"

        Tests the alert watcher by ID.
    .EXAMPLE
        Test-PfbAlertWatcher -Name "ops-team@example.com" | Select-Object result_details

        Tests the alert watcher and displays detailed results.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(ParameterSetName = 'ByName')] [string]$Name,
        [Parameter(ParameterSetName = 'ById')] [string]$Id,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $queryParams = @{}
    if ($Name) { $queryParams['names'] = $Name }
    if ($Id) { $queryParams['ids'] = $Id }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'alert-watchers/test' -QueryParams $queryParams
}
