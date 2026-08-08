param(
    [string]$ProjectPath = $PSScriptRoot
)

$ErrorActionPreference = "Stop"
$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)

$versionFile = Join-Path $ProjectPath "ProjectSettings\ProjectVersion.txt"
$versionLine = Get-Content $versionFile |
    Where-Object { $_ -match '^m_EditorVersion:\s*(.+)$' } |
    Select-Object -First 1
$unityVersion = ($versionLine -replace '^m_EditorVersion:\s*', '').Trim()

$defaultManaged = "C:\Program Files\Unity\Hub\Editor\$unityVersion\Editor\Data\Managed\UnityEngine"

if (Test-Path $defaultManaged) {
    $env:UNITY_MANAGED_PATH = $defaultManaged
    Write-Host "Using Unity references: $defaultManaged"
}
elseif (-not $env:UNITY_MANAGED_PATH) {
    Write-Warning "Unity managed DLLs were not found at the default Unity Hub path."
    Write-Warning "Set UNITY_MANAGED_PATH if Unity is installed elsewhere."
}

Push-Location $ProjectPath
try {
    dotnet tool restore
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet tool restore failed."
    }

    $generated = Join-Path $ProjectPath "docs-generated\api"
    if (Test-Path $generated) {
        Remove-Item -Recurse -Force $generated
    }

    dotnet docfx metadata Documentation\docfx.json
    if ($LASTEXITCODE -ne 0) {
        throw "DocFX generation failed with exit code $LASTEXITCODE"
    }

    Write-Host ""
    Write-Host "Generated API Markdown:" -ForegroundColor Green
    Write-Host "  $generated"
    Write-Host ""

    Get-ChildItem -Path $generated -Recurse -Filter *.md |
        ForEach-Object { Write-Host "  $($_.FullName)" }
}
finally {
    Pop-Location
}
