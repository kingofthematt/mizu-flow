param(
    [switch]$Login
)

# One-shot deploy for Mizu Flow -> GitHub Pages
$ErrorActionPreference = "Stop"

$gitCmd = "C:\Program Files\Git\cmd"
$ghCli = "C:\Program Files\GitHub CLI"
$ghExe = Join-Path $ghCli "gh.exe"
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$env:Path = "$gitCmd;$ghCli;$machinePath;$userPath"
Set-Location $PSScriptRoot

function Test-InteractiveConsole {
    return (-not [Console]::IsInputRedirected) -and ($Host.Name -ne "Server")
}

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
    $output = & $ghExe @GhArgs 2>&1
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
    if ($env:GH_TOKEN -or $env:GITHUB_TOKEN) {
        $r = Invoke-Gh api user --jq .login -AllowFailure
        if ($r[1] -eq 0 -and ($r[0] | Out-String).Trim()) { return $true }
    }
    $r = Invoke-Gh auth status --hostname github.com -AllowFailure
    return ($r[1] -eq 0)
}

function Test-IncompleteGhLogin {
    $hosts = Join-Path $env:USERPROFILE ".config\gh\hosts.yml"
    $deviceId = Join-Path $env:LOCALAPPDATA "GitHub CLI\device-id"
    return ((-not (Test-Path $hosts)) -and (Test-Path $deviceId))
}

function Invoke-GhLogin {
    Write-Host ""
    Write-Host "Starting GitHub login in your browser..." -ForegroundColor Cyan
    Write-Host "Keep this window open until you see 'Logged in as ...' here." -ForegroundColor Cyan
    Write-Host ""
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $ghExe auth login --hostname github.com --web --git-protocol https --scopes repo
    $loginExit = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if ($loginExit -ne 0) {
        Write-Host "gh auth login exited with code $loginExit." -ForegroundColor Yellow
    }
}

function Write-AuthHelp {
    Write-Host ""
    Write-Host "GitHub CLI is not authenticated." -ForegroundColor Yellow
    if (Test-IncompleteGhLogin) {
        Write-Host ""
        Write-Host "It looks like you approved login in the browser but the CLI never saved a token." -ForegroundColor Yellow
        Write-Host "Run login again and wait in this window until it finishes (do not close the terminal early)."
        Write-Host ""
    }
    Write-Host "Option A - log in once, then deploy:"
    Write-Host '  .\deploy.ps1 -Login'
    Write-Host ""
    Write-Host "Option B - manual login (same PATH this script uses):"
    Write-Host "  & `"$ghExe`" auth login --hostname github.com --web --git-protocol https --scopes repo"
    Write-Host "  .\deploy.ps1"
    Write-Host ""
    Write-Host "Option C - personal access token (repo scope):"
    Write-Host '  $env:GH_TOKEN = "ghp_..."   # then run .\deploy.ps1'
    Write-Host ""
}

Require-Command git "Install Git for Windows: https://git-scm.com/download/win"
if (-not (Test-Path $ghExe)) {
    Write-Error "GitHub CLI not found at $ghExe. Install: winget install --id GitHub.cli"
}

Write-Host "Checking GitHub auth..."
$shouldLogin = $Login -or ((Test-InteractiveConsole) -and -not (Test-GhAuth))
if (-not (Test-GhAuth)) {
    if ($shouldLogin) {
        Invoke-GhLogin
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

$result = Invoke-Gh repo view "$owner/mizu-flow" -AllowFailure
if ($result[1] -ne 0) {
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
