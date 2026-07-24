param(
    [switch]$Login
)

# One-shot deploy for Mizu Flow -> GitHub Pages
$ErrorActionPreference = "Stop"

$gitCmd = "C:\Program Files\Git\cmd"
$ghCli = "C:\Program Files\GitHub CLI"
$env:Path = "$gitCmd;$ghCli;" + $env:Path
Set-Location $PSScriptRoot

function Require-Command {
    param([string]$Name, [string]$InstallHint)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        Write-Error "$Name was not found on PATH. $InstallHint"
    }
}

function Invoke-Gh {
    param(
        [Parameter(Mandatory, ValueFromRemainingArguments = $true)]
        [string[]]$GhArgs,
        [switch]$AllowFailure
    )
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $output = & gh @GhArgs 2>&1
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if (-not $AllowFailure -and $exitCode -ne 0) {
        if ($null -ne $output -and @($output).Count -gt 0) {
            @($output) | ForEach-Object { Write-Host $_ }
        }
        throw "gh $($GhArgs -join ' ') failed (exit $exitCode)."
    }
    return ,@($output, $exitCode)
}

function Test-GhAuth {
    cmd /c "gh auth status >nul 2>nul"
    return ($LASTEXITCODE -eq 0)
}

function Write-AuthHelp {
    Write-Host ""
    Write-Host "GitHub CLI is not authenticated." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Option A - log in once, then deploy:"
    Write-Host '  $env:Path = "C:\Program Files\Git\cmd;C:\Program Files\GitHub CLI;" + $env:Path'
    Write-Host '  gh auth login --web --git-protocol https'
    Write-Host '  .\deploy.ps1'
    Write-Host ""
    Write-Host "Option B - let this script start browser login:"
    Write-Host '  .\deploy.ps1 -Login'
    Write-Host ""
    Write-Host "Option C - set GH_TOKEN (repo scope), then run .\deploy.ps1"
    Write-Host ""
}

Require-Command git "Install Git for Windows: https://git-scm.com/download/win"
Require-Command gh "Install GitHub CLI: winget install --id GitHub.cli"

Write-Host "Checking GitHub auth..."
if (-not (Test-GhAuth)) {
    if ($Login) {
        Write-Host "Not logged in. Starting GitHub device login..."
        $prev = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        gh auth login --web --git-protocol https
        $ErrorActionPreference = $prev
    }
    if (-not (Test-GhAuth)) {
        Write-AuthHelp
        exit 1
    }
}

$result = Invoke-Gh api user --jq .login
$owner = ($result[0] | Out-String).Trim()
if (-not $owner) {
    throw "Could not read GitHub username from gh api user."
}

Write-Host "Deploying as $owner/mizu-flow ..."

cmd /c "gh repo view $owner/mizu-flow >nul 2>nul"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Creating repo and pushing..."
    Invoke-Gh repo create mizu-flow --public --source=. --remote=origin --push | Out-Null
} else {
    Write-Host "Repo exists; pushing main..."
    git remote remove origin 2>$null
    git remote add origin "https://github.com/$owner/mizu-flow.git"
    git push -u origin main
    if ($LASTEXITCODE -ne 0) { throw "git push failed (exit $LASTEXITCODE)." }
}

Write-Host "Enabling GitHub Pages (legacy / root)..."
$pagesFields = @(
    "-f", "build_type=legacy",
    "-f", "source[branch]=main",
    "-f", "source[path]=/"
)
$result = Invoke-Gh -AllowFailure api -X POST "repos/$owner/mizu-flow/pages" @pagesFields
if ($result[1] -ne 0) {
    Invoke-Gh api -X PUT "repos/$owner/mizu-flow/pages" @pagesFields | Out-Null
}

$pagesUrl = "https://$owner.github.io/mizu-flow/"
Write-Host ""
Write-Host "Done! Site will be live at: $pagesUrl"
Write-Host "(Pages can take 1-2 minutes to build.)"