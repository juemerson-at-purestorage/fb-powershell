#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../PureStorageFlashBladePowerShell.psd1" -Force
    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Get-PfbPolicyAllMember' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It '-MemberType offers tab-completion for all five known spec-documented values (not a hard ValidateSet, since the spec value set has grown over time)' {
        $attr = (Get-Command Get-PfbPolicyAllMember).Parameters['MemberType'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] }
        $attr | Should -Not -BeNullOrEmpty

        $validateSetAttr = (Get-Command Get-PfbPolicyAllMember).Parameters['MemberType'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $validateSetAttr | Should -BeNullOrEmpty

        $completions = & $attr.ScriptBlock 'Get-PfbPolicyAllMember' 'MemberType' '' $null @{}
        ($completions | Sort-Object) | Should -Be (@(
            'file-systems', 'file-system-snapshots', 'file-system-replica-links',
            'object-store-users', 'object-store-accounts'
        ) | Sort-Object)
    }

    It 'does NOT reject a value outside the known completion list (non-exhaustive, no hard validation)' {
        { Get-PfbPolicyAllMember -MemberType 'some-future-member-type' -Array $fakeArray } | Should -Not -Throw
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $QueryParams['member_types'] -eq 'some-future-member-type'
        }
    }

    It 'passes valid -MemberType values through to the query string, comma-joined' {
        Get-PfbPolicyAllMember -MemberType 'file-systems', 'object-store-accounts' -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Endpoint -eq 'policies-all/members' -and $QueryParams['member_types'] -eq 'file-systems,object-store-accounts'
        }
    }

    It 'omits -MemberType from the query string when not specified' {
        Get-PfbPolicyAllMember -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            -not $QueryParams.ContainsKey('member_types')
        }
    }
}
