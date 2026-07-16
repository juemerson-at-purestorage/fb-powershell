<#
.SYNOPSIS
    AST-based inventory of every typed parameter across Public/**/*.ps1, with best-effort
    resolution of each parameter's REST "wire name" (the request-body or query-string key
    it's assigned to). Dot-sourced by tools/Build-PfbFieldCmdletMap.ps1 and its Pester
    tests, parallel to tools/lib/PfbSpecTools.ps1 and tools/lib/PfbValueEnumTools.ps1.

.DESCRIPTION
    Every cmdlet in this module follows one of a small number of body-construction
    patterns (confirmed by direct inspection of New-PfbAlertWatcher, Get-PfbArrayPerformance,
    New-PfbBucket, New-PfbNetworkInterface, New-PfbFileSystem, Update-PfbFileSystem):

        if ($Param) { $body['wire_name'] = $Param }
        if ($Param) { $body['wire_name'] = @($Param) }         # array parameters
        if ($queryParams.ContainsKey(...)) ...                  # not matched, no enum data anyway
        $queryParams['wire_name'] = $Param

    A parameter is classified into exactly one Surface:
      - 'Typed': a wire name was resolved via a direct (optionally @()-wrapped) assignment.
      - 'AttributesOnly': the cmdlet has an -Attributes hashtable escape hatch and this
        parameter's value is NOT assigned via a simple pattern above (e.g. it's piped
        through ForEach-Object first, like New-PfbNetworkInterface's -AttachedServers) --
        deliberately NOT guessed at, since over-matching here would misattribute a value
        enum to the wrong field.
      - 'TypedUnresolved': no -Attributes escape hatch exists AND no simple assignment was
        found -- surfaced so a human can look, never silently dropped.

    -Array and -Attributes are never returned as inventory records themselves -- they are
    plumbing, not spec-documented fields with values to validate.
#>

# Deliberately NOT Set-StrictMode -- same reasoning as PfbSpecTools.ps1 / PfbValueEnumTools.ps1.

function Get-PfbWireNameForParameter {
    <#
    .SYNOPSIS
        Finds the request-body or query-string key a given parameter is assigned to
        inside a cmdlet function body, or $null if no simple assignment pattern matches.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.FunctionDefinitionAst]$FunctionAst,

        [Parameter(Mandatory)]
        [string]$ParameterName
    )

    $assignments = $FunctionAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left -is [System.Management.Automation.Language.IndexExpressionAst]
    }, $true)

    foreach ($assign in $assignments) {
        $indexExpr = $assign.Left
        $targetVar = $indexExpr.Target -as [System.Management.Automation.Language.VariableExpressionAst]
        if (-not $targetVar) { continue }
        if ($targetVar.VariablePath.UserPath -notin @('body', 'queryParams')) { continue }

        $keyExpr = $indexExpr.Index -as [System.Management.Automation.Language.StringConstantExpressionAst]
        if (-not $keyExpr) { continue }

        $rhsText = $assign.Right.Extent.Text.Trim()
        $simple = '$' + $ParameterName
        $wrapped = '@(' + $simple + ')'

        if ($rhsText -eq $simple -or $rhsText -eq $wrapped) {
            return $keyExpr.Value
        }
    }

    return $null
}

function Get-PfbCmdletParameterInventory {
    <#
    .SYNOPSIS
        Inventories every typed parameter (excluding -Array/-Attributes themselves)
        across every function defined under -PublicDirectory.
    .OUTPUTS
        [PSCustomObject]@{ File; Cmdlet; Parameter; HasValidateSet; ValidateSetValues;
        WireName; Surface }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PublicDirectory
    )

    $results = [System.Collections.Generic.List[object]]::new()
    $files = Get-ChildItem -Path $PublicDirectory -Filter '*.ps1' -Recurse -File

    foreach ($file in $files) {
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)

        $functionAsts = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)

        foreach ($funcAst in $functionAsts) {
            $paramBlock = $funcAst.Body.ParamBlock
            if (-not $paramBlock) { continue }

            $hasAttributesParam = [bool]($paramBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Attributes' })

            foreach ($p in $paramBlock.Parameters) {
                $paramName = $p.Name.VariablePath.UserPath
                if ($paramName -in @('Array', 'Attributes')) { continue }

                $validateSetValues = $null
                foreach ($attr in $p.Attributes) {
                    if ($attr -is [System.Management.Automation.Language.AttributeAst] -and $attr.TypeName.Name -eq 'ValidateSet') {
                        $validateSetValues = @($attr.PositionalArguments | ForEach-Object { $_.SafeGetValue() })
                    }
                }

                $wireName = Get-PfbWireNameForParameter -FunctionAst $funcAst -ParameterName $paramName

                $surface = if ($wireName) { 'Typed' }
                elseif ($hasAttributesParam) { 'AttributesOnly' }
                else { 'TypedUnresolved' }

                $results.Add([PSCustomObject]@{
                    File              = $file.FullName
                    Cmdlet            = $funcAst.Name
                    Parameter         = $paramName
                    HasValidateSet    = [bool]$validateSetValues
                    ValidateSetValues = $validateSetValues
                    WireName          = $wireName
                    Surface           = $surface
                })
            }
        }
    }

    return $results
}
