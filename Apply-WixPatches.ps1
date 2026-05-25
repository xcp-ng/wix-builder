$ErrorActionPreference = 'Stop'
$patches = Get-Content .\wix-builder\patches\series | Where-Object { $_ -and $_ -notlike "#*" }
$patches | ForEach-Object {
    Write-Host "Applying $_"
    git apply .\wix-builder\patches\$_
    if ($LASTEXITCODE -ne 0) {
        throw "git apply failed with exit code $LASTEXITCODE"
    }
}
