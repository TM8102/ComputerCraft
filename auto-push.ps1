# Go to the folder this script lives in
Set-Location $PSScriptRoot

# Add all changed files
git add .

# Check if anything actually changed
$changes = git status --porcelain

if ($changes) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    git commit -m "Auto update $timestamp"

    if ($LASTEXITCODE -eq 0) {
        git push
    }
}