$ErrorActionPreference = 'Stop'
$patches = Get-Content .\wix-builder\patches\series | Where-Object { $_ -and $_ -notlike "#*" }
$patches | ForEach-Object {
    $Env:GIT_COMMITTER_NAME = "wix-builder"
    $Env:GIT_COMMITTER_EMAIL = "wix-builder@invalid.invalid"
    git am .\wix-builder\patches\$_
    if ($LASTEXITCODE -ne 0) {
        throw "git am failed with exit code $LASTEXITCODE"
    }
}
