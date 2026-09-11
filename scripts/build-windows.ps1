param([ValidateSet('win-x64', 'win-arm64')][string]$Runtime = 'win-x64')
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$destination = Join-Path $repo "artifacts/$Runtime"
dotnet test (Join-Path $repo 'Companion/Riff.Tests') -c Release
if ($LASTEXITCODE -ne 0) { throw 'Core tests failed.' }
if ($IsWindows -or $env:OS -eq 'Windows_NT') {
    dotnet test (Join-Path $repo 'Companion/Riff.WindowsTests') -c Release
    if ($LASTEXITCODE -ne 0) { throw 'Windows integration tests failed. Close any running Riff companion and retry.' }
}
dotnet publish (Join-Path $repo 'Companion/Riff.Companion') -c Release -r $Runtime --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o $destination
if ($LASTEXITCODE -ne 0) { throw 'Publishing failed.' }
Copy-Item (Join-Path $repo 'docs/WINDOWS-QUICKSTART.txt') $destination
Copy-Item (Join-Path $repo 'docs/THIRD-PARTY.md') $destination
Copy-Item (Join-Path $repo 'docs/licenses') $destination -Recurse -Force
Get-ChildItem $destination -Filter '*.pdb' | Remove-Item
$archive = Join-Path $repo "artifacts/Riff-$Runtime.zip"
Compress-Archive -Path "$destination/*" -DestinationPath $archive -Force
Write-Host "Ready: $archive"
