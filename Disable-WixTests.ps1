<#
.SYNOPSIS
    Surgically neuters all test projects from the WiX build graph to ensure a production-only build.

.DESCRIPTION
    This script performs the following actions:
    1. Prunes test ProjectReferences from all Traversal (_t.proj) files.
    2. Prunes test projects from all Solution (.slnx) files using XML manipulation.
    3. Deletes packages.config in test directories to block NuGet downloads.
    4. Removes -warnaserror from all build command (.cmd) files.
    5. Ensure Extension Builds in Traversal Projects.
#>

$ErrorActionPreference = "Stop"
$RootDir = Get-Item "."
$SrcDir = Join-Path $RootDir.FullName "src"

Write-Host "--- NEUTERING TESTS FOR PRODUCTION BUILD ---" -ForegroundColor Cyan

# 1. Prune Traversal (_t.proj) files
Write-Host "[1/5] Pruning Traversal projects..." -ForegroundColor Yellow
$traversalFiles = Get-ChildItem -Path $SrcDir -Filter "*_t.proj" -Recurse
foreach ($file in $traversalFiles) {
    $newContent = Get-Content $file.FullName | Where-Object {
        $_ -notmatch '<ProjectReference Include=".*?test.*?".*?/>'
    }
    Set-Content $file.FullName $newContent
    Write-Host "  - Processed: $($file.FullName)" -ForegroundColor Gray
}

# 2. Prune Solution (.slnx) files
Write-Host "[2/5] Pruning Solution (.slnx) files..." -ForegroundColor Yellow
$slnxFiles = Get-ChildItem -Path $SrcDir -Filter "*.slnx" -Recurse
foreach ($file in $slnxFiles) {
    [xml]$xml = Get-Content $file.FullName -Raw

    # Find and remove <Project> elements whose Path contains "test" (case-insensitive).
    # We collect into a static array first because XmlNodeList is live and mutating
    # during iteration causes skipped nodes.
    $testProjects = @($xml.SelectNodes("//Project[contains(translate(@Path, 'TEST', 'test'), 'test')]"))
    foreach ($project in $testProjects) {
        $project.ParentNode.RemoveChild($project) | Out-Null
    }

    $xml.Save($file.FullName)
    Write-Host "  - Processed: $($file.FullName) ($($testProjects.Count) test projects removed)" -ForegroundColor Gray
}

# 3. Disable packages.config in test directories
Write-Host "[3/5] Deleting test packages.config..." -ForegroundColor Yellow
$packageConfigs = Get-ChildItem -Path $SrcDir -Filter "packages.config" -Recurse
foreach ($file in $packageConfigs) {
    if ($file.FullName -match "test") {
        Remove-Item $file.FullName
        Write-Host "  - Deleted: $($file.FullName)" -ForegroundColor Gray
    }
}

# 4. Remove -warnaserror from .cmd files
Write-Host "[4/5] Removing -warnaserror from scripts..." -ForegroundColor Yellow
$cmdFiles = Get-ChildItem -Path $RootDir -Filter "*.cmd" -Recurse
foreach ($file in $cmdFiles) {
    $newContent = Get-Content $file.FullName | ForEach-Object {
        $_ -replace '-warnaserror\s*', ""
    }
    Set-Content $file.FullName $newContent
    Write-Host "  - Processed: $($file.FullName)" -ForegroundColor Gray
}

# 5. Ensure Extension Builds in Traversal Projects
Write-Host "[5/5] Ensuring Extension builds..." -ForegroundColor Yellow
$extTraversalFiles = Get-ChildItem -Path (Join-Path $SrcDir "ext") -Filter "*_t.proj" -Recurse
foreach ($file in $extTraversalFiles) {
    $content = Get-Content $file.FullName
    $newLines = @()

    foreach ($line in $content) {
        # Match ProjectReference with at least Include and either Targets="Pack" or NoBuild
        if ($line -match '<ProjectReference\s+Include="([^"]+\.csproj)"(.*)/>') {
            $csprojPath = $Matches[1]
            $attributes = $Matches[2]

            # If it's a Pack reference and we don't already have a regular build for this DLL in this file
            if ($attributes -match 'Targets="Pack"') {
                $escapedPath = [regex]::Escape($csprojPath)
                # Does the file contain a reference to this project WITHOUT Targets="Pack"?
                if ($content -notmatch "<ProjectReference Include=""$escapedPath""(?![^>]*Targets=""Pack"")") {
                    # Create a clean build-only reference
                    $buildRef = $line -replace 'Targets="Pack"', '' -replace 'Properties="NoBuild=true"', '' -replace '\s{2,}', ' ' -replace '\s+/>', ' />'
                    if ($buildRef -ne $line) {
                        $newLines += $buildRef
                    }
                }
            }
        }
        $newLines += $line
    }

    Set-Content $file.FullName $newLines
    Write-Host "  - Processed: $($file.FullName)" -ForegroundColor Gray
}

Write-Host "--- NEUTERING COMPLETE ---" -ForegroundColor Green
Write-Host "Run 'devbuild.cmd Release' to verify." -ForegroundColor Cyan
