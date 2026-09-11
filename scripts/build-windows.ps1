param(
    [ValidateSet('win-x64', 'win-arm64')][string]$Runtime = 'win-x64',
    [ValidatePattern('^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-dev)?$')][string]$Version = '0.0.0-dev',
    [string]$ChangelogPath
)
$ErrorActionPreference = 'Stop'
if ($Version -notlike '*-dev' -and -not $ChangelogPath) { throw 'Release builds require -ChangelogPath.' }
if ($ChangelogPath -and -not (Test-Path $ChangelogPath -PathType Leaf)) { throw "Changelog not found: $ChangelogPath" }
$repo = Split-Path $PSScriptRoot -Parent
$destination = Join-Path $repo "artifacts/$Runtime"
dotnet test (Join-Path $repo 'Companion/Riff.Tests') -c Release
if ($LASTEXITCODE -ne 0) { throw 'Core tests failed.' }
if ($IsWindows -or $env:OS -eq 'Windows_NT') {
    dotnet test (Join-Path $repo 'Companion/Riff.WindowsTests') -c Release
    if ($LASTEXITCODE -ne 0) { throw 'Windows integration tests failed. Close any running Riff companion and retry.' }
}
if (Test-Path $destination) { Remove-Item $destination -Recurse -Force }
dotnet publish (Join-Path $repo 'Companion/Riff.Companion') -c Release -r $Runtime --self-contained true -p:Version=$Version -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o $destination
if ($LASTEXITCODE -ne 0) { throw 'Publishing failed.' }
if ($ChangelogPath) { Copy-Item $ChangelogPath (Join-Path $destination 'CHANGELOG.md') }
Copy-Item (Join-Path $repo 'docs/WINDOWS-QUICKSTART.txt') $destination
Copy-Item (Join-Path $repo 'docs/THIRD-PARTY.md') $destination
Copy-Item (Join-Path $repo 'docs/licenses') $destination -Recurse -Force
Get-ChildItem $destination -Filter '*.pdb' | Remove-Item
$archive = Join-Path $repo "artifacts/Riff-$Version-$Runtime.zip"
Compress-Archive -Path "$destination/*" -DestinationPath $archive -Force
Write-Host "Ready: $archive"
