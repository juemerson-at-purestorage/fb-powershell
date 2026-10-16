@{
    SchemaVersion = 1
    Sequences = @(
        @{
            Name  = 'file-system-lifecycle'
            Notes = 'Proof run for the live-test PR trigger.'
            Steps = @(
                @{ Cmdlet = 'New-PfbFileSystem'; Arguments = @{ Name = 'pslivetest-fs-1'; Provisioned = 1073741824 }; ExpectedOutcome = 'Pass' }
                @{ Cmdlet = 'Get-PfbFileSystem'; Arguments = @{ Name = 'pslivetest-fs-1' }; ExpectedOutcome = 'Pass'; ExpectedCount = 1; ExpectedProperties = @{ provisioned = 1073741824 } }
                @{ Cmdlet = 'Get-PfbFileSystem'; Arguments = @{ Name = 'pslivetest-does-not-exist' }; ExpectedOutcome = 'Fail'; ExpectedError = 'does not exist'; Notes = 'Deliberate negative: proves the name selector reached the wire.' }
            )
            Teardown = @(
                @{ Cmdlet = 'Update-PfbFileSystem'; Arguments = @{ Name = 'pslivetest-fs-1'; Destroyed = $true } }
                @{ Cmdlet = 'Remove-PfbFileSystem'; Arguments = @{ Name = 'pslivetest-fs-1'; Eradicate = $true } }
            )
        }
    )
}
