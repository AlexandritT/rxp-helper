param(
    [string]$WoWPath = 'I:\World of Warcraft_2'
)
$ErrorActionPreference = 'Stop'
$source = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\RXPDJBridge'))
$addons = Join-Path $WoWPath '_forever_\Interface\AddOns'
if (-not (Test-Path -LiteralPath $addons -PathType Container)) {
    throw "Forever AddOns directory not found: $addons"
}
foreach ($dependency in @('RXPGuides', 'ForeverDungeonJournal')) {
    if (-not (Test-Path -LiteralPath (Join-Path $addons $dependency) -PathType Container)) {
        throw "Required addon is missing: $dependency"
    }
}
$destination = Join-Path $addons 'RXPDJBridge'
New-Item -Path $destination -ItemType Directory -Force | Out-Null
foreach ($name in @('RXPDJBridge.toc', 'Index.lua', 'Bridge.lua')) {
    $inputFile = Join-Path $source $name
    $outputFile = Join-Path $destination $name
    Copy-Item -LiteralPath $inputFile -Destination $outputFile -Force
    if ((Get-FileHash -LiteralPath $inputFile).Hash -ne (Get-FileHash -LiteralPath $outputFile).Hash) {
        throw "Installed file verification failed: $name"
    }
}
Write-Output "Installed and verified: $destination"
