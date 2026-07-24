# One-shot deploy for Mizu Flow -> GitHub Pages
$ErrorActionPreference = "Stop"

$env:Path = "C:\Program Files\Git\cmd;C:\Program Files\GitHub CLI;" + $env:Path
Set-Location $PSScriptRoot

Write-Host "Checking GitHub auth..."
gh auth status 2>$null
if ($LASTEXITCODE -ne 0) {
  Write-Host "Opening browser for GitHub login..."
  gh auth login --web --git-protocol https
}

$owner = (gh api user --jq .login)
Write-Host "Creating repo and pushing..."
$repoExists = gh repo view "$owner/mizu-flow" 2>$null
if ($LASTEXITCODE -ne 0) {
  gh repo create mizu-flow --public --source=. --remote=origin --push
} else {
  git remote remove origin 2>$null
  git remote add origin "https://github.com/$owner/mizu-flow.git"
  git push -u origin main
}

Write-Host "Enabling GitHub Pages..."
gh api -X POST "repos/$owner/mizu-flow/pages" -f build_type=legacy -f source[branch]=main -f source[path]=/ 2>$null
if ($LASTEXITCODE -ne 0) {
  gh api -X PUT "repos/$owner/mizu-flow/pages" -f build_type=legacy -f source[branch]=main -f source[path]=/
}

$pagesUrl = "https://$owner.github.io/mizu-flow/"
Write-Host ""
Write-Host "Done! Site will be live at: $pagesUrl"
Write-Host "(Pages can take 1-2 minutes to build.)"
