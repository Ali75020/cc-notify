#Requires -Version 5.1
<#
.SYNOPSIS
    CC Notify interactive setup wizard — guided installation with live preview.
.DESCRIPTION
    Same installer logic as install.ps1 but with a richer terminal experience:
    step-by-step progress, phrase preview, and colored output.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Logging (same log file as install.ps1)
$logDir  = Join-Path $env:USERPROFILE ".claude\logs"
$null    = New-Item -ItemType Directory -Path $logDir -Force -ErrorAction SilentlyContinue
$logFile = Join-Path $logDir "cc-notify-install.log"

function Log {
    param([string]$Msg)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts | [wizard] $Msg" | Tee-Object -FilePath $logFile -Append | Out-Null
}

function Pause {
    param([string]$Prompt = "Press Enter to continue...")
    Read-Host $Prompt | Out-Null
}

# ─── Welcome ──────────────────────────────────────────────────────────────────

Clear-Host
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║         CC Notify  —  Setup Wizard                  ║" -ForegroundColor Cyan
Write-Host "  ║   Windows toast notifications for Claude Code        ║" -ForegroundColor Cyan
Write-Host "  ║   with random funny phrases and a coffee sticker     ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "  This wizard will:" -ForegroundColor White
Write-Host "    • Check prerequisites (PowerShell, BurntToast)" -ForegroundColor Gray
Write-Host "    • Ask how you want your phrases"                 -ForegroundColor Gray
Write-Host "    • Install files into ~/.claude/hooks/"           -ForegroundColor Gray
Write-Host "    • Merge hooks into ~/.claude/settings.json"      -ForegroundColor Gray
Write-Host "    • Send 3 test notifications"                     -ForegroundColor Gray
Write-Host ""

$proceed = Read-Host "  Ready? [Y/n]"
if ($proceed -ne "Y" -and $proceed -ne "y" -and $proceed -ne "") {
    Write-Host "  Cancelled." -ForegroundColor Yellow
    exit 0
}

Log "=== CC Notify Setup Wizard Start ==="

# ─── Step 1 : Pre-flight ─────────────────────────────────────────────────────

Write-Host ""
Write-Host "  [1/7] Pre-flight checks" -ForegroundColor Cyan

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "  ERROR: PowerShell 5.1+ required." -ForegroundColor Red; exit 1
}
Write-Host "  ✓ PowerShell $($PSVersionTable.PSVersion)" -ForegroundColor Green

$osVer = [System.Environment]::OSVersion.Version
if ($osVer.Major -lt 10) {
    Write-Host "  ERROR: Windows 10 or 11 required." -ForegroundColor Red; exit 1
}
Write-Host "  ✓ Windows $osVer" -ForegroundColor Green

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$hasGh = $false
if (Get-Command gh -ErrorAction SilentlyContinue) {
    $ghTest = & gh auth status 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ GitHub CLI authenticated" -ForegroundColor Green
        $hasGh = $true
    } else {
        Write-Host "  ! GitHub CLI present but not authenticated (repo push will be skipped)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  i GitHub CLI not found (repo push will be skipped)" -ForegroundColor Gray
}
Log "Pre-flight OK"

# ─── Step 2 : BurntToast ─────────────────────────────────────────────────────

Write-Host ""
Write-Host "  [2/7] BurntToast module" -ForegroundColor Cyan

if (-not (Get-Module BurntToast -ListAvailable)) {
    Write-Host "  Installing BurntToast..." -ForegroundColor Yellow
    try {
        Install-Module -Name BurntToast -Force -AllowClobber -ErrorAction Stop
        Write-Host "  ✓ BurntToast installed" -ForegroundColor Green
        Log "BurntToast installed"
    } catch {
        Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red; exit 1
    }
} else {
    Write-Host "  ✓ BurntToast already installed" -ForegroundColor Green
    Log "BurntToast already present"
}

# ─── Step 3 : Phrases ────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  [3/7] Phrase configuration" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Choose your notification phrases:" -ForegroundColor White
Write-Host ""
Write-Host "  1  Default phrases (Ali's curated set)"     -ForegroundColor Green
Write-Host "     'Done cooking ☕ — your code is ready.'"  -ForegroundColor DarkGray
Write-Host "     'Ship it. Unless you need more chaos. 🚀'" -ForegroundColor DarkGray
Write-Host "     ... and 5 more Stop phrases + 5 Permission phrases" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  2  Custom phrases (opens Notepad to edit)"  -ForegroundColor Yellow
Write-Host ""

$choice = Read-Host "  Select [1/2]"

$defaultPhrases = @{
    stop       = @(
        "Done cooking ☕ — your code is ready.",
        "Voilà! Your masterpiece is served. 🍽️",
        "I didn't break anything. Probably. 🤞",
        "All done — no refunds on the bugs though. 🐛",
        "Fresh off the compiler. Still warm. 🔥",
        "Ship it. Unless you need more chaos. 🚀",
        "I coded, you chilled. Balance restored. 😎"
    )
    permission = @(
        "Permission checkpoint 🔐 — approve me maybe?",
        "Before I wreck stuff — mind approving? 🛑",
        "Knock knock. Permission? 🚪",
        "I promise I'll be careful. Mostly. 👀",
        "Little checkpoint: your call, boss. 🎯"
    )
}

$phrasesObj = $defaultPhrases

if ($choice -eq "2") {
    $tmpFile = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.json'
    $defaultPhrases | ConvertTo-Json -Depth 5 | Out-File $tmpFile -Encoding UTF8
    Write-Host ""
    Write-Host "  Opening Notepad — edit the JSON, save, then close Notepad." -ForegroundColor Cyan
    & notepad.exe $tmpFile
    try {
        $loaded     = Get-Content $tmpFile -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        $phrasesObj = @{ stop = @($loaded.stop); permission = @($loaded.permission) }
        Write-Host "  ✓ Custom phrases loaded" -ForegroundColor Green
        Log "Custom phrases loaded"
    } catch {
        Write-Host "  ! Invalid JSON — falling back to defaults" -ForegroundColor Yellow
        Log "Custom phrases invalid; using defaults"
    }
    Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "  ✓ Default phrases selected" -ForegroundColor Green
    Log "Default phrases selected"
}

# Phrase preview
Write-Host ""
Write-Host "  Sample phrases (what your notifications will say):" -ForegroundColor Cyan
Write-Host "    Stop:       $(Get-Random -InputObject $phrasesObj.stop)" -ForegroundColor DarkGray
Write-Host "    Permission: $(Get-Random -InputObject $phrasesObj.permission)" -ForegroundColor DarkGray
Write-Host ""

Pause "  Happy with these? Press Enter to continue..."

# ─── Step 4 : Copy files ─────────────────────────────────────────────────────

Write-Host ""
Write-Host "  [4/7] Installing files" -ForegroundColor Cyan

$hookDir   = Join-Path $env:USERPROFILE ".claude\hooks"
$assetsDir = Join-Path $hookDir "assets"
$null = New-Item -ItemType Directory -Path $hookDir   -Force -ErrorAction SilentlyContinue
$null = New-Item -ItemType Directory -Path $assetsDir -Force -ErrorAction SilentlyContinue

# Icon
$iconSrc  = Join-Path $scriptDir "assets\claude_coffe_icon.png"
$iconDest = Join-Path $assetsDir "claude_coffe_icon.png"

if (-not (Test-Path $iconSrc)) {
    Write-Host "  ERROR: assets/claude_coffe_icon.png not found." -ForegroundColor Red; exit 1
}

$iconBytes = [System.IO.File]::ReadAllBytes($iconSrc)
if ($iconBytes[0] -ne 0x89 -or $iconBytes[1] -ne 0x50 -or $iconBytes[2] -ne 0x4E -or $iconBytes[3] -ne 0x47) {
    Write-Host "  ! Icon may not be valid PNG" -ForegroundColor Yellow
}

Copy-Item -Path $iconSrc -Destination $iconDest -Force
Write-Host "  ✓ Icon   → $iconDest" -ForegroundColor Green

# notify.ps1
$notifySrc  = Join-Path $scriptDir "notify.ps1"
$notifyDest = Join-Path $hookDir   "notify.ps1"

if (-not (Test-Path $notifySrc)) {
    Write-Host "  ERROR: notify.ps1 not found in repo." -ForegroundColor Red; exit 1
}

Copy-Item -Path $notifySrc -Destination $notifyDest -Force
Write-Host "  ✓ Script → $notifyDest" -ForegroundColor Green
Log "Files copied"

# ─── Step 5 : phrases.json ───────────────────────────────────────────────────

Write-Host ""
Write-Host "  [5/7] Writing phrases.json" -ForegroundColor Cyan

$phrasesFile = Join-Path $hookDir "phrases.json"
$phrasesObj | ConvertTo-Json -Depth 5 | Out-File -FilePath $phrasesFile -Encoding UTF8 -Force
Write-Host "  ✓ $phrasesFile" -ForegroundColor Green
Log "phrases.json written"

# ─── Step 6 : Merge settings.json ────────────────────────────────────────────

Write-Host ""
Write-Host "  [6/7] Updating ~/.claude/settings.json" -ForegroundColor Cyan

$settingsFile = Join-Path $env:USERPROFILE ".claude\settings.json"

# Backup
if (Test-Path $settingsFile) {
    $backup = "$settingsFile.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item -Path $settingsFile -Destination $backup -Force
    Write-Host "  ✓ Backup → $backup" -ForegroundColor Green
    Log "Backup: $backup"
}

# Load
try {
    if (Test-Path $settingsFile) {
        $settings = Get-Content $settingsFile -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    } else {
        $settings = @{ hooks = @{} }
    }
} catch {
    Write-Host "  ERROR: Cannot parse settings.json." -ForegroundColor Red; exit 1
}

if (-not $settings["hooks"])                      { $settings["hooks"] = @{} }
if (-not $settings["hooks"]["Stop"])              { $settings["hooks"]["Stop"] = @() }
if (-not $settings["hooks"]["PermissionRequest"]) { $settings["hooks"]["PermissionRequest"] = @() }

$notifyPath = "$env:USERPROFILE\.claude\hooks\notify.ps1"
$cmdStop    = "& `"$notifyPath`" -Event `"stop`" -Title `"Claude Code`""
$cmdPerm    = "& `"$notifyPath`" -Event `"permission`" -Title `"Claude Code`""

function Test-HookExists {
    param([string]$EventType)
    if ($settings["hooks"][$EventType] -is [array]) {
        foreach ($entry in $settings["hooks"][$EventType]) {
            if ($entry -is [hashtable] -and $entry["hooks"] -is [array]) {
                foreach ($hook in $entry["hooks"]) {
                    if ($hook.command -like "*notify.ps1*" -and $hook.command -like "*-Event*") {
                        return $true
                    }
                }
            }
        }
    }
    return $false
}

if (-not (Test-HookExists "Stop")) {
    $settings["hooks"]["Stop"] += @{
        matcher = ""
        hooks   = @(@{ type = "command"; command = $cmdStop; shell = "powershell" })
    }
    Write-Host "  ✓ Stop hook added" -ForegroundColor Green
    Log "Stop hook added"
} else {
    Write-Host "  i Stop hook already present (skipped)" -ForegroundColor Gray
}

if (-not (Test-HookExists "PermissionRequest")) {
    $settings["hooks"]["PermissionRequest"] += @{
        matcher = ""
        hooks   = @(@{ type = "command"; command = $cmdPerm; shell = "powershell" })
    }
    Write-Host "  ✓ PermissionRequest hook added" -ForegroundColor Green
    Log "PermissionRequest hook added"
} else {
    Write-Host "  i PermissionRequest hook already present (skipped)" -ForegroundColor Gray
}

# Preview
Write-Host ""
Write-Host "  Hooks preview:" -ForegroundColor Cyan
Write-Host "    Stop               → $cmdStop" -ForegroundColor DarkGray
Write-Host "    PermissionRequest  → $cmdPerm" -ForegroundColor DarkGray
Write-Host ""

$confirm = Read-Host "  Apply changes to settings.json? [Y/n]"
if ($confirm -ne "Y" -and $confirm -ne "y" -and $confirm -ne "") {
    Write-Host "  Cancelled — no changes written." -ForegroundColor Yellow
    Log "Cancelled at settings merge step."
    exit 0
}

$json = $settings | ConvertTo-Json -Depth 15
[System.IO.File]::WriteAllText($settingsFile, $json, [System.Text.UTF8Encoding]::new($false))
Write-Host "  ✓ settings.json updated" -ForegroundColor Green
Log "settings.json written"

# ─── Step 7 : Test notifications ─────────────────────────────────────────────

Write-Host ""
Write-Host "  [7/7] Testing notifications" -ForegroundColor Cyan
Write-Host "  Sending 3 test notifications — watch the bottom-right corner of your screen." -ForegroundColor White
Write-Host ""

for ($i = 1; $i -le 3; $i++) {
    try {
        & $notifyDest -Event "stop" -Title "Claude Code" 2>&1 | Out-Null
        Write-Host "  ✓ Notification $i sent" -ForegroundColor Green
        Log "Test $i sent"
        Start-Sleep -Seconds 2
    } catch {
        Write-Host "  ! Test $i failed — check BurntToast." -ForegroundColor Yellow
        Log "Test $i failed: $_"
    }
}

# ─── Optional GitHub push ─────────────────────────────────────────────────────

if ($hasGh) {
    Write-Host ""
    $push = Read-Host "  Push repo to GitHub as Ali7020/cc-notify? [Y/n]"
    if ($push -eq "Y" -or $push -eq "y" -or $push -eq "") {
        Write-Host "  Creating GitHub repo..." -ForegroundColor Cyan
        try {
            Push-Location $scriptDir
            if (-not (Test-Path ".git")) { & git init 2>&1 | Out-Null }
            & git add .    2>&1 | Out-Null
            & git commit -m "Initial commit: cc-notify" 2>&1 | Out-Null
            & gh repo create Ali7020/cc-notify --public --source=. --push 2>&1 | Out-Null
            Pop-Location
            Write-Host "  ✓ https://github.com/Ali7020/cc-notify" -ForegroundColor Green
            Log "GitHub repo created: Ali7020/cc-notify"
        } catch {
            Write-Host "  ! GitHub push failed: $_" -ForegroundColor Yellow
            Log "GitHub push failed: $_"
            Pop-Location
        }
    }
}

# ─── Done ─────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║                  Setup complete!                     ║" -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  What to do next:" -ForegroundColor White
Write-Host "    1. Restart Claude Code" -ForegroundColor Gray
Write-Host "    2. Run  claude /hooks  to confirm hooks are loaded" -ForegroundColor Gray
Write-Host "    3. Close Claude Code — a toast notification should appear" -ForegroundColor Gray
Write-Host "       (watch bottom-right corner, different phrase each time)" -ForegroundColor Gray
Write-Host ""
Write-Host "  Customise:  $phrasesFile" -ForegroundColor DarkCyan
Write-Host "  Logs:       $logFile"     -ForegroundColor DarkGray
Write-Host ""

Pause "  Press Enter to exit."
Log "=== CC Notify Setup Wizard Complete ==="
