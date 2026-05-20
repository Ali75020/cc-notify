#Requires -Version 5.1
<#
.SYNOPSIS
    CC Notify installer — wires Claude Code toast notifications on Windows.
.DESCRIPTION
    Installs notify.ps1, the coffee icon, and phrases.json into ~/.claude/hooks/,
    then merges Stop and PermissionRequest hooks into ~/.claude/settings.json.
    Never overwrites your existing settings — always backs up and merges.
.EXAMPLE
    irm https://raw.githubusercontent.com/Ali7020/cc-notify/main/install.ps1 | iex
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Logging
$logDir  = Join-Path $env:USERPROFILE ".claude\logs"
$null    = New-Item -ItemType Directory -Path $logDir -Force -ErrorAction SilentlyContinue
$logFile = Join-Path $logDir "cc-notify-install.log"

function Log {
    param([string]$Msg)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts | $Msg" | Tee-Object -FilePath $logFile -Append | Out-Null
}

Log "=== CC Notify Installer Start ==="

# ─── Step 1 : Pre-flight ──────────────────────────────────────────────────────

Log "Step 1: Pre-flight checks"

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Log "ERROR: PowerShell 5.1+ required."
    Write-Host "ERROR: PowerShell 5.1+ required." -ForegroundColor Red
    exit 1
}
Log "OK  PowerShell $($PSVersionTable.PSVersion)"

$osVer = [System.Environment]::OSVersion.Version
if ($osVer.Major -lt 10) {
    Log "ERROR: Windows 10 or 11 required."
    Write-Host "ERROR: Windows 10 or 11 required." -ForegroundColor Red
    exit 1
}
Log "OK  Windows $osVer"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoName  = Split-Path -Leaf $scriptDir
if ($repoName -ne "cc-notify") {
    Log "WARN: Running from '$repoName' directory (expected 'cc-notify')."
    Write-Host "WARN: Expected to run from the 'cc-notify' directory." -ForegroundColor Yellow
    $proceed = Read-Host "Continue anyway? [Y/n]"
    if ($proceed -ne "Y" -and $proceed -ne "y" -and $proceed -ne "") {
        Log "Cancelled by user."; exit 0
    }
}

$hasGh = $false
if (Get-Command gh -ErrorAction SilentlyContinue) {
    Log "OK  GitHub CLI found"
    $ghTest = & gh auth status 2>&1
    if ($LASTEXITCODE -eq 0) {
        Log "OK  GitHub authenticated"
        $hasGh = $true
    } else {
        Log "WARN: GitHub CLI present but not authenticated."
        Write-Host "WARN: GitHub CLI not authenticated — repo push will be skipped." -ForegroundColor Yellow
    }
} else {
    Log "INFO: GitHub CLI not found — repo push will be skipped."
}

# ─── Step 2 : BurntToast ─────────────────────────────────────────────────────

Log "Step 2: BurntToast module"

if (-not (Get-Module BurntToast -ListAvailable)) {
    Log "BurntToast not installed. Installing..."
    Write-Host "Installing BurntToast..." -ForegroundColor Cyan
    try {
        Install-Module -Name BurntToast -Force -AllowClobber -ErrorAction Stop
        Log "OK  BurntToast installed"
    } catch {
        Log "ERROR: BurntToast install failed: $_"
        Write-Host "ERROR: Could not install BurntToast. Try: Install-Module BurntToast -Force" -ForegroundColor Red
        exit 1
    }
} else {
    Log "OK  BurntToast already installed"
}

# ─── Step 3 : Phrase configuration ───────────────────────────────────────────

Log "Step 3: Phrase configuration"

Write-Host ""
Write-Host "Phrase mode:" -ForegroundColor Cyan
Write-Host "  1. Default phrases (Ali's curated set — recommended)" -ForegroundColor Green
Write-Host "  2. Custom phrases (edit in Notepad)"                   -ForegroundColor Yellow
Write-Host ""

$choice = Read-Host "Select [1/2]"

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
    Log "Custom phrases selected."
    $tmpFile = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.json'
    $defaultPhrases | ConvertTo-Json -Depth 5 | Out-File -FilePath $tmpFile -Encoding UTF8
    Write-Host "Opening Notepad — edit phrases, save, then close Notepad." -ForegroundColor Cyan
    & notepad.exe $tmpFile
    try {
        $loaded   = Get-Content $tmpFile -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        $phrasesObj = @{ stop = @($loaded.stop); permission = @($loaded.permission) }
        Log "OK  Custom phrases loaded."
    } catch {
        Log "WARN: Invalid JSON in custom file. Using defaults."
        Write-Host "WARN: Could not parse custom phrases — using defaults." -ForegroundColor Yellow
        $phrasesObj = $defaultPhrases
    }
    Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
} else {
    Log "OK  Using default phrases."
}

# ─── Step 4 : Copy assets and script ─────────────────────────────────────────

Log "Step 4: Copying files"

$hookDir   = Join-Path $env:USERPROFILE ".claude\hooks"
$assetsDir = Join-Path $hookDir "assets"
$null = New-Item -ItemType Directory -Path $hookDir   -Force -ErrorAction SilentlyContinue
$null = New-Item -ItemType Directory -Path $assetsDir -Force -ErrorAction SilentlyContinue
Log "OK  Hook directory: $hookDir"

# Icon
$iconSrc  = Join-Path $scriptDir "assets\claude_coffe_icon.png"
$iconDest = Join-Path $assetsDir "claude_coffe_icon.png"

if (-not (Test-Path $iconSrc)) {
    Log "ERROR: Icon not found at $iconSrc"
    Write-Host "ERROR: assets/claude_coffe_icon.png missing from repo." -ForegroundColor Red
    exit 1
}

$iconBytes = [System.IO.File]::ReadAllBytes($iconSrc)
if ($iconBytes[0] -ne 0x89 -or $iconBytes[1] -ne 0x50 -or $iconBytes[2] -ne 0x4E -or $iconBytes[3] -ne 0x47) {
    Log "WARN: Icon does not have PNG magic bytes."
    Write-Host "WARN: Icon may not be a valid PNG." -ForegroundColor Yellow
} else {
    Log "OK  Icon is valid PNG"
}

Copy-Item -Path $iconSrc -Destination $iconDest -Force
Log "OK  Icon copied to $iconDest"

# notify.ps1
$notifySrc  = Join-Path $scriptDir "notify.ps1"
$notifyDest = Join-Path $hookDir   "notify.ps1"

if (-not (Test-Path $notifySrc)) {
    Log "ERROR: notify.ps1 not found at $notifySrc"
    Write-Host "ERROR: notify.ps1 missing from repo." -ForegroundColor Red
    exit 1
}

Copy-Item -Path $notifySrc -Destination $notifyDest -Force
Log "OK  notify.ps1 copied to $notifyDest"

# ─── Step 5 : Write phrases.json ─────────────────────────────────────────────

Log "Step 5: Writing phrases.json"

$phrasesFile = Join-Path $hookDir "phrases.json"
try {
    $phrasesObj | ConvertTo-Json -Depth 5 | Out-File -FilePath $phrasesFile -Encoding UTF8 -Force
    Log "OK  phrases.json written to $phrasesFile"
} catch {
    Log "ERROR: Could not write phrases.json: $_"
    Write-Host "ERROR: Could not write phrases.json." -ForegroundColor Red
    exit 1
}

# ─── Step 6 : Merge settings.json ────────────────────────────────────────────

Log "Step 6: Merging ~/.claude/settings.json"

$settingsFile = Join-Path $env:USERPROFILE ".claude\settings.json"

# Warn about project-local settings if present
$projSettings = Join-Path (Get-Location) ".claude\settings.json"
if (Test-Path $projSettings) {
    Log "NOTE: Found project-local .claude/settings.json — this installer only modifies global settings."
    Write-Host "NOTE: Found project-local .claude/settings.json (unchanged)." -ForegroundColor Gray
}

# Backup
if (Test-Path $settingsFile) {
    $backupFile = "$settingsFile.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item -Path $settingsFile -Destination $backupFile -Force
    Log "OK  Backup: $backupFile"
} else {
    Log "INFO: No existing settings.json — will create."
    $backupFile = $null
}

# Load or init
try {
    if (Test-Path $settingsFile) {
        $settings = Get-Content $settingsFile -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    } else {
        $settings = @{ hooks = @{} }
    }
    Log "OK  Settings loaded"
} catch {
    Log "ERROR: Cannot parse settings.json: $_"
    Write-Host "ERROR: Corrupted settings.json — restore from backup and retry." -ForegroundColor Red
    exit 1
}

# Ensure hooks structure
if (-not $settings["hooks"])                       { $settings["hooks"] = @{} }
if (-not $settings["hooks"]["Stop"])               { $settings["hooks"]["Stop"] = @() }
if (-not $settings["hooks"]["PermissionRequest"])  { $settings["hooks"]["PermissionRequest"] = @() }

# Hook commands (use -Event so notify.ps1 picks random phrase)
$notifyPath   = "$env:USERPROFILE\.claude\hooks\notify.ps1"
$cmdStop      = "& `"$notifyPath`" -Event `"stop`" -Title `"Claude Code`""
$cmdPerm      = "& `"$notifyPath`" -Event `"permission`" -Title `"Claude Code`""

# Duplicate detection: both "notify.ps1" and "-Event" must appear in command
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

$stopExists = Test-HookExists "Stop"
$permExists = Test-HookExists "PermissionRequest"

if (-not $stopExists) {
    $settings["hooks"]["Stop"] += @{
        matcher = ""
        hooks   = @(@{ type = "command"; command = $cmdStop; shell = "powershell" })
    }
    Log "OK  Stop hook added"
} else {
    Log "SKIP Stop hook already present"
}

if (-not $permExists) {
    $settings["hooks"]["PermissionRequest"] += @{
        matcher = ""
        hooks   = @(@{ type = "command"; command = $cmdPerm; shell = "powershell" })
    }
    Log "OK  PermissionRequest hook added"
} else {
    Log "SKIP PermissionRequest hook already present"
}

# Dry-run preview
Write-Host ""
Write-Host "Preview — updated hooks:" -ForegroundColor Cyan
$settings["hooks"] | ConvertTo-Json -Depth 10 | Write-Host
Write-Host ""

$confirm = Read-Host "Apply these changes? [Y/n]"
if ($confirm -ne "Y" -and $confirm -ne "y" -and $confirm -ne "") {
    Log "Cancelled at dry-run step."
    if ($backupFile) { Write-Host "No changes written. Backup preserved: $backupFile" }
    exit 0
}

# Write back (UTF-8, no BOM)
try {
    $json = $settings | ConvertTo-Json -Depth 15
    [System.IO.File]::WriteAllText($settingsFile, $json, [System.Text.UTF8Encoding]::new($false))
    Log "OK  settings.json written"
} catch {
    Log "ERROR: Could not write settings.json: $_"
    Write-Host "ERROR: Could not write settings.json." -ForegroundColor Red
    exit 1
}

# ─── Step 7 : Test notification ──────────────────────────────────────────────

Log "Step 7: Testing notification"

Write-Host ""
Write-Host "Sending 3 test notifications to verify phrase randomization..." -ForegroundColor Cyan

for ($i = 1; $i -le 3; $i++) {
    try {
        & $notifyDest -Event "stop" -Title "Claude Code" 2>&1 | Out-Null
        Log "Test $i sent"
        Write-Host "  Test $i ✓" -ForegroundColor Green
        Start-Sleep -Seconds 2
    } catch {
        Log "WARN: Test $i failed: $_"
        Write-Host "  Test $i — check BurntToast installation." -ForegroundColor Yellow
    }
}

# ─── Step 8 (optional) : GitHub repo ─────────────────────────────────────────

if ($hasGh) {
    Log "Step 8: Creating GitHub repo"
    try {
        Push-Location $scriptDir
        if (-not (Test-Path ".git")) {
            & git init 2>&1 | Out-Null
            Log "OK  git init"
        }
        & git add . 2>&1 | Out-Null
        & git commit -m "Initial commit: cc-notify" 2>&1 | Out-Null
        Log "OK  git commit"
        & gh repo create Ali7020/cc-notify --public --source=. --push 2>&1 | Out-Null
        Log "OK  GitHub repo created: Ali7020/cc-notify"
        Write-Host ""
        Write-Host "Repo published: https://github.com/Ali7020/cc-notify" -ForegroundColor Green
        Pop-Location
    } catch {
        Log "WARN: GitHub step failed: $_"
        Write-Host "WARN: GitHub repo creation failed — push manually later." -ForegroundColor Yellow
        Pop-Location
    }
}

# ─── Summary ─────────────────────────────────────────────────────────────────

Log "=== CC Notify Installer Complete ==="

Write-Host ""
Write-Host "✓ Installation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Restart Claude Code to load the new hooks."
Write-Host "  2. Run  claude /hooks  to verify they are registered."
Write-Host "  3. Close Claude Code and watch the bottom-right corner of your screen."
Write-Host "     A toast notification with a random funny phrase should appear."
Write-Host ""
Write-Host "Customise phrases : $phrasesFile" -ForegroundColor Gray
Write-Host "Log file          : $logFile"     -ForegroundColor Gray
Write-Host ""
