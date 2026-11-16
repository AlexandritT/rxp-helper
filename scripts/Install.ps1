param(
    [string]$WoWPath = 'I:\World of Warcraft_2',
    [string]$BackupRoot = (Join-Path $env:USERPROFILE '.t3\backups\rxp-helper')
)
$ErrorActionPreference = 'Stop'
$source = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\RestedXPHelper'))
$addons = Join-Path $WoWPath '_forever_\Interface\AddOns'
if (-not (Test-Path -LiteralPath $addons -PathType Container)) {
    throw "Forever AddOns directory not found: $addons"
}
if (-not (Test-Path -LiteralPath (Join-Path $addons 'RXPGuides') -PathType Container)) {
    throw 'Required addon is missing: RXPGuides'
}
$files = @('RestedXPHelper.toc', 'Index.lua', 'Core.lua', 'QuestTooltips.lua', 'OrphanQuests.lua')
foreach ($name in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $source $name) -PathType Leaf)) {
        throw "Source file is missing: $name"
    }
}
$addons = (Resolve-Path -LiteralPath $addons).ProviderPath
$BackupRoot = [IO.Path]::GetFullPath($BackupRoot)
foreach ($addonName in @('RXPDJBridge', 'RestedXPHelper')) {
    $existing = [IO.Path]::GetFullPath((Join-Path $addons $addonName))
    if (-not (Test-Path -LiteralPath $existing -PathType Container)) { continue }
    $backup = [IO.Path]::GetFullPath((Join-Path $BackupRoot ($addonName + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))))
    if ([IO.Path]::GetDirectoryName($existing) -ne $addons -or
        [IO.Path]::GetDirectoryName($backup) -ne $BackupRoot) {
        throw 'Addon backup path is outside the intended directory.'
    }
    New-Item -Path $BackupRoot -ItemType Directory -Force | Out-Null
    Move-Item -LiteralPath $existing -Destination $backup
    Write-Output "Backed up: $backup"
}
$destination = Join-Path $addons 'RestedXPHelper'
New-Item -Path $destination -ItemType Directory -Force | Out-Null
foreach ($name in $files) {
    $inputFile = Join-Path $source $name
    $outputFile = Join-Path $destination $name
    Copy-Item -LiteralPath $inputFile -Destination $outputFile -Force
    if ((Get-FileHash -LiteralPath $inputFile).Hash -ne (Get-FileHash -LiteralPath $outputFile).Hash) {
        throw "Installed file verification failed: $name"
    }
}
Write-Output "Installed and verified: $destination"
