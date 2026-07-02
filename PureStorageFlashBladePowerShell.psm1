#Requires -Version 5.1

# Module-scoped connection state
$script:PfbDefaultArray = $null
$script:PfbArrays = @{}

# Dot-source all private functions
$privatePath = Join-Path $PSScriptRoot 'Private'
if (Test-Path $privatePath) {
    Get-ChildItem -Path $privatePath -Filter '*.ps1' -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        . $_.FullName
    }
}

# Dot-source all public functions
$publicPath = Join-Path $PSScriptRoot 'Public'
$publicFunctions = @()
if (Test-Path $publicPath) {
    $publicFiles = Get-ChildItem -Path $publicPath -Filter '*.ps1' -Recurse -ErrorAction SilentlyContinue
    foreach ($file in $publicFiles) {
        . $file.FullName
    }
    $publicFunctions = $publicFiles.BaseName
}

# Export public functions and private functions used by tests
$functionsToExport = @($publicFunctions)

# Include private helper functions that are directly tested
if (Get-Command ConvertTo-PfbVersionObject -ErrorAction SilentlyContinue) {
    $functionsToExport += 'ConvertTo-PfbVersionObject'
}

if ($functionsToExport.Count -gt 0) {
    Export-ModuleMember -Function $functionsToExport
}
