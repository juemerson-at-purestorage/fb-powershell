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

    Each 'Typed' record also carries a best-effort Endpoint/Method: the literal
    -Endpoint/-Method arguments of the Invoke-PfbApiRequest call the parameter's
    resolved body/queryParams variable actually feeds, IF every such call in the
    function agrees on exactly one (Method, Endpoint) pair. Left $null (never guessed)
    when the variable feeds zero calls, or more than one distinct pair -- e.g.
    Get-PfbNode's try/catch fallback that reuses the same $queryParams against two
    genuinely different endpoints ('nodes' then 'blades'). This is what lets
    Build-PfbFieldCmdletMap.ps1 resolve an 'inline-parameter'-kind value-enum record
    (see tools/lib/PfbValueEnumTools.ps1), which is keyed by exact endpoint identity,
    against the one specific cmdlet parameter that calls it.
#>

# Deliberately NOT Set-StrictMode -- same reasoning as PfbSpecTools.ps1 / PfbValueEnumTools.ps1.

function Test-PfbAssignmentGuardedBySwitch {
    <#
    .SYNOPSIS
        True if $Assignment is lexically inside an `if ($ParameterName) { ... }` clause
        whose condition is exactly a bare reference to $ParameterName -- the guard shape
        Test-PfbAssignmentGuardedBySwitch's caller requires before trusting a literal
        string assignment as switch-derived.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Assignment,

        [Parameter(Mandatory)]
        [string]$ParameterName
    )

    $expectedCondition = '$' + $ParameterName
    $node = $Assignment.Parent
    while ($node) {
        if ($node -is [System.Management.Automation.Language.IfStatementAst]) {
            foreach ($clause in $node.Clauses) {
                if ($clause.Item1.Extent.Text.Trim() -eq $expectedCondition) {
                    $withinBody = $clause.Item2.FindAll({ param($n) $n -eq $Assignment }, $true)
                    if (@($withinBody).Count -gt 0) { return $true }
                }
            }
        }
        $node = $node.Parent
    }
    return $false
}

function Get-PfbWireNameForParameter {
    <#
    .SYNOPSIS
        Finds the request-body or query-string key a given parameter is assigned to
        inside a cmdlet function body, or $null if no simple assignment pattern matches.
    .OUTPUTS
        $null, or [PSCustomObject]@{ WireName; TargetVariable } -- TargetVariable is the
        literal variable name the assignment targeted ('body' or 'queryParams'), needed
        by Get-PfbEndpointForVariable to find the specific Invoke-PfbApiRequest call(s)
        that variable is later passed to.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.FunctionDefinitionAst]$FunctionAst,

        [Parameter(Mandatory)]
        [string]$ParameterName,

        [switch]$IsSwitchParameter
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

        $isJoinOfParameter = $false
        # AssignmentStatementAst.Right is a StatementAst -- for a single-expression RHS (the
        # only shape these cmdlets ever use) the parser always wraps it in a CommandExpressionAst,
        # never exposing a BinaryExpressionAst directly, so unwrap one level before casting.
        $rhsExpr = $assign.Right
        if ($rhsExpr -is [System.Management.Automation.Language.CommandExpressionAst]) {
            $rhsExpr = $rhsExpr.Expression
        }
        $rhsBinary = $rhsExpr -as [System.Management.Automation.Language.BinaryExpressionAst]
        if ($rhsBinary -and $rhsBinary.Operator -eq [System.Management.Automation.Language.TokenKind]::Join) {
            $joinLeft = $rhsBinary.Left -as [System.Management.Automation.Language.VariableExpressionAst]
            if ($joinLeft -and $joinLeft.VariablePath.UserPath -eq $ParameterName) {
                $isJoinOfParameter = $true
            }
        }

        $isSwitchLiteral = $false
        if ($IsSwitchParameter -and $rhsExpr -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            if (Test-PfbAssignmentGuardedBySwitch -Assignment $assign -ParameterName $ParameterName) {
                $isSwitchLiteral = $true
            }
        }

        if ($rhsText -eq $simple -or $rhsText -eq $wrapped -or $isJoinOfParameter -or $isSwitchLiteral) {
            return [PSCustomObject]@{
                WireName       = $keyExpr.Value
                TargetVariable = $targetVar.VariablePath.UserPath
            }
        }
    }

    return $null
}

function Get-PfbEndpointForVariable {
    <#
    .SYNOPSIS
        Finds the (Method, Endpoint) pair a body/queryParams variable is passed to via
        Invoke-PfbApiRequest -Body/-QueryParams within a function, IF every such call
        agrees on exactly one (Method, Endpoint) pair.
    .DESCRIPTION
        Never guesses: returns $null when the variable feeds zero Invoke-PfbApiRequest
        calls, or more than one call with a DIFFERENT (Method, Endpoint) pair (e.g.
        Get-PfbNode's try/catch fallback that reuses the same $queryParams against two
        genuinely different endpoints, 'nodes' then 'blades' -- correctly ambiguous,
        not a case to force-pick one of). Only literal, unquoted-bareword-or-quoted-
        string -Method/-Endpoint arguments are recognized, matching the exclusively
        literal style every cmdlet in this repo actually uses for both.
    .OUTPUTS
        $null, or [PSCustomObject]@{ Method; Endpoint }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.FunctionDefinitionAst]$FunctionAst,

        [Parameter(Mandatory)]
        [string]$TargetVariable
    )

    $targetParamName = switch ($TargetVariable) {
        'body' { 'Body' }
        'queryParams' { 'QueryParams' }
        default { $null }
    }
    if (-not $targetParamName) { return $null }

    $commands = $FunctionAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.CommandAst] -and
        $node.GetCommandName() -eq 'Invoke-PfbApiRequest'
    }, $true)

    $pairs = [System.Collections.Generic.List[string]]::new()

    foreach ($cmd in $commands) {
        $elements = $cmd.CommandElements
        $usesVariable = $false
        $method = $null
        $endpoint = $null

        for ($i = 0; $i -lt $elements.Count; $i++) {
            $el = $elements[$i]
            if ($el -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
            $next = if ($i + 1 -lt $elements.Count) { $elements[$i + 1] } else { $null }
            if (-not $next) { continue }

            if ($el.ParameterName -eq $targetParamName -and
                $next -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $next.VariablePath.UserPath -eq $TargetVariable) {
                $usesVariable = $true
            }
            elseif ($el.ParameterName -eq 'Method' -and $next -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                $method = $next.Value
            }
            elseif ($el.ParameterName -eq 'Endpoint' -and $next -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                $endpoint = $next.Value
            }
        }

        if ($usesVariable -and $method -and $endpoint) {
            $pairs.Add("$($method.ToUpperInvariant())|$endpoint")
        }
    }

    $distinct = @($pairs | Select-Object -Unique)
    if ($distinct.Count -ne 1) { return $null }

    $parts = $distinct[0] -split '\|', 2
    return [PSCustomObject]@{ Method = $parts[0]; Endpoint = $parts[1] }
}

function Get-PfbCmdletParameterInventory {
    <#
    .SYNOPSIS
        Inventories every typed parameter (excluding -Array/-Attributes themselves)
        across every function defined under -PublicDirectory.
    .OUTPUTS
        [PSCustomObject]@{ File; Cmdlet; Parameter; HasValidateSet; ValidateSetValues;
        WireName; Surface; Endpoint; Method }

        Endpoint/Method are $null unless the parameter's wire-name assignment resolved
        to exactly one Invoke-PfbApiRequest call's endpoint (see
        Get-PfbEndpointForVariable) -- never guessed.
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

                $isSwitch = $p.StaticType -eq [System.Management.Automation.SwitchParameter]
                $wireInfo = Get-PfbWireNameForParameter -FunctionAst $funcAst -ParameterName $paramName -IsSwitchParameter:$isSwitch
                $wireName = if ($wireInfo) { $wireInfo.WireName } else { $null }

                $endpointInfo = if ($wireInfo) { Get-PfbEndpointForVariable -FunctionAst $funcAst -TargetVariable $wireInfo.TargetVariable } else { $null }

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
                    Endpoint          = if ($endpointInfo) { $endpointInfo.Endpoint } else { $null }
                    Method            = if ($endpointInfo) { $endpointInfo.Method } else { $null }
                })
            }
        }
    }

    return $results
}
