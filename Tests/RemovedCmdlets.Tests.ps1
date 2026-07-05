#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force
}

Describe 'Broken/duplicate policy cmdlets are removed' {
    It 'no longer exports <Name>' -ForEach @(
        @{ Name = 'New-PfbFileSystemSnapshotPolicy' }
        @{ Name = 'New-PfbPolicyMember' }
        @{ Name = 'Remove-PfbPolicyMember' }
        @{ Name = 'Get-PfbPolicyMember' }
    ) {
        (Get-Command -Module PureStorageFlashBladePowerShell -Name $Name -ErrorAction SilentlyContinue) |
            Should -BeNullOrEmpty
    }
}

Describe 'Replacement cmdlets are exported' {
    It 'exports <Name>' -ForEach @(
        @{ Name = 'New-PfbPolicyFileSystem' }
        @{ Name = 'Remove-PfbPolicyFileSystem' }
    ) {
        (Get-Command -Module PureStorageFlashBladePowerShell -Name $Name -ErrorAction SilentlyContinue) |
            Should -Not -BeNullOrEmpty
    }
}

Describe 'Retained correct cmdlets are untouched' {
    It 'still exports <Name>' -ForEach @(
        @{ Name = 'Remove-PfbFileSystemSnapshotPolicy' }
        @{ Name = 'Get-PfbPolicyFileSystem' }
        @{ Name = 'New-PfbPolicyFileSystemReplicaLink' }
        @{ Name = 'Remove-PfbPolicyFileSystemReplicaLink' }
    ) {
        (Get-Command -Module PureStorageFlashBladePowerShell -Name $Name -ErrorAction SilentlyContinue) |
            Should -Not -BeNullOrEmpty
    }
}
