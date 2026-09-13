<#
.SYNOPSIS
    Post-processes DocFX-generated Markdown into Docusaurus-ready Markdown.

.DESCRIPTION
    This script is intentionally narrow in scope.

    It:
      - Reads each .md file under -InputDir
      - Extracts the first H1 heading
      - Removes DocFX's leading <a id="..."></a> anchor from the title only
      - Creates Docusaurus front matter
      - Leaves the original Markdown body untouched
      - Copies DocFX toc.yml / toc.yaml files unchanged
      - Clears the output directory before writing
      - Fails clearly if input is missing, empty, malformed, or partially invalid

    The DocFX anchors inside the document body are deliberately preserved
    because they are used by DocFX-generated member links.

.PARAMETER InputDir
    Directory containing raw DocFX Markdown.

    Default:
        docs-generated/docfx-raw

.PARAMETER OutputDir
    Directory where Docusaurus-ready Markdown will be written.

    Default:
        docs-generated/api

.PARAMETER StripKindPrefix
    If supplied, sidebar_label removes the leading DocFX API kind from titles.

    For example:

        Class DocumentationExample
            becomes
        DocumentationExample

        Namespace Platformer.Gameplay
            becomes
        Platformer.Gameplay

    The page title itself remains unchanged.
#>

[CmdletBinding()]
param(
    [string]$InputDir = "docs-generated/docfx-raw",
    [string]$OutputDir = "docs-generated/api",
    [switch]$StripKindPrefix
)

$ErrorActionPreference = "Stop"

function Fail {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Error $Message
    exit 1
}

function Get-RelativePath {
    param(
        [Parameter(Mandatory)]
        [string]$BasePath,

        [Parameter(Mandatory)]
        [string]$FullPath
    )

    $resolvedBase = (Resolve-Path -LiteralPath $BasePath).Path
    $resolvedFull = (Resolve-Path -LiteralPath $FullPath).Path

    return [System.IO.Path]::GetRelativePath(
        $resolvedBase,
        $resolvedFull
    )
}

function Escape-YamlDoubleQuotedString {
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    # YAML double-quoted strings use backslash escaping.
    $escaped = $Value.Replace('\', '\\')
    $escaped = $escaped.Replace('"', '\"')

    return $escaped
}

function Repair-GlobalNamespaceLinks {
    param(
        [Parameter(Mandatory)]
        [string]$OutputDir
    )

    $markdownFiles = @(
        Get-ChildItem `
            -LiteralPath $OutputDir `
            -Filter "*.md" `
            -Recurse `
            -File
    )

    # Use a reference-type object so the regex replacement callback can
    # update these values without PowerShell scope issues.
    $stats = @{
        RepairedCount   = 0
        UnresolvedLinks = [System.Collections.Generic.List[string]]::new()
    }

    foreach ($file in $markdownFiles) {
        $content = Get-Content `
            -LiteralPath $file.FullName `
            -Raw

        $fileDirectory = Split-Path -Parent $file.FullName

        # Match relative Markdown links such as:
        #
        #   [Foo](Foo.md)
        #   [Foo](Foo.md#some-anchor)
        #
        # External URLs and absolute site paths are ignored.
        $pattern = '\]\((?<path>[^)#?]+\.md)(?<fragment>#[^)]+)?\)'

        $newContent = [regex]::Replace(
            $content,
            $pattern,
            {
                param($match)

                $linkPath = $match.Groups["path"].Value
                $fragment = $match.Groups["fragment"].Value

                # DocFX may Markdown-escape punctuation inside link targets.
                # The filesystem path itself does not contain those escape characters.
                $filesystemLinkPath = $linkPath.Replace('\-', '-')

                # Ignore URLs and absolute/site-root paths.
                if (
                    $linkPath -match '^[a-zA-Z][a-zA-Z0-9+.-]*://' -or
                    $linkPath.StartsWith('/')
                ) {
                    return $match.Value
                }

                $normalTarget = Join-Path `
                    $fileDirectory `
                    $filesystemLinkPath

                # The original link already resolves correctly.
                if (Test-Path -LiteralPath $normalTarget -PathType Leaf) {
                    return $match.Value
                }

                $linkDirectory = Split-Path -Parent $filesystemLinkPath
                $linkFileName = Split-Path -Leaf $filesystemLinkPath

                if ([string]::IsNullOrWhiteSpace($linkDirectory)) {
                    $globalLinkPath = "Global.$linkFileName"
                }
                else {
                    $globalLinkPath = Join-Path `
                        $linkDirectory `
                        "Global.$linkFileName"
                }

                $globalTarget = Join-Path `
                    $fileDirectory `
                    $globalLinkPath

                # DocFX sometimes emits a global-namespace link without the
                # Global. filename prefix even though that is the actual file.
                if (Test-Path -LiteralPath $globalTarget -PathType Leaf) {
                    $stats.RepairedCount++

                    Write-Host "Repaired global link: $linkPath -> $globalLinkPath"

                    # Markdown paths should always use forward slashes.
                    $globalLinkPath = $globalLinkPath.Replace('\', '/')

                    return "]($globalLinkPath$fragment)"
                }

                $stats.UnresolvedLinks.Add(
                    "$($file.Name): $linkPath$fragment"
                )

                return $match.Value
            }
        )

        if ($newContent -ne $content) {
            Set-Content `
                -LiteralPath $file.FullName `
                -Value $newContent `
                -NoNewline `
                -Encoding utf8
        }
    }

    return @{
        RepairedCount   = $stats.RepairedCount
        UnresolvedLinks = @($stats.UnresolvedLinks)
    }
}

# ----------------------------------------------------------------------
# Validate input
# ----------------------------------------------------------------------

if (-not (Test-Path -LiteralPath $InputDir -PathType Container)) {
    Fail "Input directory '$InputDir' does not exist. Did the DocFX generation step run?"
}

$mdFiles = @(
    Get-ChildItem `
        -LiteralPath $InputDir `
        -Filter "*.md" `
        -Recurse `
        -File
)

if ($mdFiles.Count -eq 0) {
    Fail "No Markdown files were found under '$InputDir'. DocFX output looks empty or invalid."
}

Write-Host "DocFX -> Docusaurus post-processing"
Write-Host "----------------------------------"
Write-Host "Input directory : $InputDir"
Write-Host "Output directory: $OutputDir"
Write-Host "Markdown files  : $($mdFiles.Count)"

# ----------------------------------------------------------------------
# Prepare clean output
# ----------------------------------------------------------------------

if (Test-Path -LiteralPath $OutputDir) {
    Write-Host ""
    Write-Host "Clearing existing output directory..."

    Remove-Item `
        -LiteralPath $OutputDir `
        -Recurse `
        -Force
}

New-Item `
    -ItemType Directory `
    -Path $OutputDir `
    -Force |
    Out-Null

# ----------------------------------------------------------------------
# Process Markdown files
# ----------------------------------------------------------------------

$errors = @()
$processedCount = 0

foreach ($file in $mdFiles) {
    $relativePath = Get-RelativePath `
        -BasePath $InputDir `
        -FullPath $file.FullName

    Write-Host "Processing: $relativePath"

    $content = Get-Content `
        -LiteralPath $file.FullName `
        -Raw

    if ([string]::IsNullOrWhiteSpace($content)) {
        $errors += "Empty Markdown file: $relativePath"
        continue
    }

    # Raw DocFX Markdown should not already contain Docusaurus front matter.
    #
    # Accept both LF and CRLF immediately after the opening delimiter.
    if ($content -match '^\uFEFF?---\r?\n') {
        $errors += "Unexpected existing front matter: $relativePath"
        continue
    }

    # DocFX normally emits:
    #
    #   # <a id="Namespace_Type"></a> Class Type
    #
    # but we also accept a normal H1 without the anchor.
    $h1Match = [regex]::Match(
        $content,
        '(?m)^#\s+(.+?)\s*$'
    )

    if (-not $h1Match.Success) {
        $errors += "No H1 heading found: $relativePath"
        continue
    }

    $rawHeadingText = $h1Match.Groups[1].Value

    # Remove only the DocFX anchor from the title metadata.
    #
    # The original document body is not changed.
    $cleanTitle = [regex]::Replace(
        $rawHeadingText,
        '<a\s+id="[^"]*"\s*>\s*</a>\s*',
        ''
    )

    # Defensive cleanup in case DocFX places some other inline HTML in the H1.
    $cleanTitle = [regex]::Replace(
        $cleanTitle,
        '<[^>]+>',
        ''
    ).Trim()

    if ([string]::IsNullOrWhiteSpace($cleanTitle)) {
        $errors += "H1 resolved to an empty title after cleanup: $relativePath"
        continue
    }

    $sidebarLabel = $cleanTitle

    if ($StripKindPrefix) {
        $sidebarLabel = [regex]::Replace(
            $sidebarLabel,
            '^(Class|Struct|Interface|Enum|Delegate|Namespace)\s+',
            ''
        )
    }

    if ([string]::IsNullOrWhiteSpace($sidebarLabel)) {
        $errors += "Sidebar label resolved to an empty string: $relativePath"
        continue
    }

    $titleYaml = Escape-YamlDoubleQuotedString $cleanTitle
    $labelYaml = Escape-YamlDoubleQuotedString $sidebarLabel

    $frontMatter = @"
---
title: "$titleYaml"
sidebar_label: "$labelYaml"
---

"@

    # The original DocFX body is preserved exactly as generated.
    $newContent = $frontMatter + $content

    $targetPath = Join-Path `
        $OutputDir `
        $relativePath

    $targetDirectory = Split-Path `
        -Parent `
        $targetPath

    if (-not (Test-Path -LiteralPath $targetDirectory)) {
        New-Item `
            -ItemType Directory `
            -Path $targetDirectory `
            -Force |
            Out-Null
    }

    Set-Content `
        -LiteralPath $targetPath `
        -Value $newContent `
        -NoNewline `
        -Encoding utf8

    $processedCount++
}

# ----------------------------------------------------------------------
# Copy support files
# ----------------------------------------------------------------------

$supportFiles = @(
    Get-ChildItem `
        -LiteralPath $InputDir `
        -Recurse `
        -File |
    Where-Object {
        $_.Name -ieq "toc.yml" -or
        $_.Name -ieq "toc.yaml"
    }
)

foreach ($supportFile in $supportFiles) {
    $relativePath = Get-RelativePath `
        -BasePath $InputDir `
        -FullPath $supportFile.FullName

    $targetPath = Join-Path `
        $OutputDir `
        $relativePath

    $targetDirectory = Split-Path `
        -Parent `
        $targetPath

    if (-not (Test-Path -LiteralPath $targetDirectory)) {
        New-Item `
            -ItemType Directory `
            -Path $targetDirectory `
            -Force |
            Out-Null
    }

    Copy-Item `
        -LiteralPath $supportFile.FullName `
        -Destination $targetPath `
        -Force

    Write-Host "Copied support file: $relativePath"
}

# ----------------------------------------------------------------------
# Repair DocFX global-namespace links
# ----------------------------------------------------------------------

$linkRepairResult = Repair-GlobalNamespaceLinks `
    -OutputDir $OutputDir

$repairedLinkCount = $linkRepairResult.RepairedCount
$unresolvedLinks = @($linkRepairResult.UnresolvedLinks)

if ($unresolvedLinks.Count -gt 0) {
    Write-Host ""
    Write-Host "Unresolved local Markdown links:" -ForegroundColor Yellow

    foreach ($unresolvedLink in $unresolvedLinks) {
        Write-Host "  - $unresolvedLink" -ForegroundColor Yellow
    }
}

# ----------------------------------------------------------------------
# Final validation
# ----------------------------------------------------------------------

if ($errors.Count -gt 0) {
    Write-Host ""
    Write-Host "Encountered $($errors.Count) problem file(s):" -ForegroundColor Red

    foreach ($errorMessage in $errors) {
        Write-Host "  - $errorMessage" -ForegroundColor Red
    }

    Fail "Post-processing failed validation. Wrote $processedCount of $($mdFiles.Count) Markdown file(s) before validation completed."
}

if ($processedCount -ne $mdFiles.Count) {
    Fail "Expected to process $($mdFiles.Count) Markdown file(s), but processed $processedCount."
}

$outputMarkdownFiles = @(
    Get-ChildItem `
        -LiteralPath $OutputDir `
        -Filter "*.md" `
        -Recurse `
        -File
)

if ($outputMarkdownFiles.Count -ne $mdFiles.Count) {
    Fail "Output validation failed. Expected $($mdFiles.Count) Markdown file(s), found $($outputMarkdownFiles.Count)."
}

Write-Host ""
Write-Host "Post-processing complete."
Write-Host "Processed Markdown files : $processedCount"
Write-Host "Copied support files     : $($supportFiles.Count)"
Write-Host "Global links repaired    : $repairedLinkCount"
Write-Host "Unresolved local links   : $($unresolvedLinks.Count)"
Write-Host "Output directory         : $OutputDir"
