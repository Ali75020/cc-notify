param(
    [string]$Title = "Claude Code",
    [string]$Message = "",
    [string]$ImagePath = "",
    [string]$Event = "stop"
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if ([string]::IsNullOrWhiteSpace($ImagePath)) {
    $ImagePath = Join-Path $scriptDir "assets\claude_coffe_icon.png"
}

$imageExists = Test-Path $ImagePath

# Load phrases from phrases.json or fall back to built-in defaults
$phrasesFile = Join-Path $scriptDir "phrases.json"

$builtInPhrases = @{
    "stop" = @(
        "Done cooking — your code is ready.",
        "Voila! Your masterpiece is served.",
        "I didn't break anything. Probably.",
        "All done — no refunds on the bugs though.",
        "Fresh off the compiler. Still warm.",
        "Ship it. Unless you need more chaos.",
        "I coded, you chilled. Balance restored."
    )
    "permission" = @(
        "Permission checkpoint — approve me maybe?",
        "Before I wreck stuff — mind approving?",
        "Knock knock. Permission?",
        "I promise I'll be careful. Mostly.",
        "Little checkpoint: your call, boss."
    )
}

if ([string]::IsNullOrWhiteSpace($Message)) {
    $phrases = $builtInPhrases

    if (Test-Path $phrasesFile) {
        try {
            $loaded = Get-Content $phrasesFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $phrases = @{
                "stop" = @($loaded.stop)
                "permission" = @($loaded.permission)
            }
        } catch {
            # silently fall back to built-in
        }
    }

    $phraseArray = $phrases[$Event]
    if ($phraseArray -and $phraseArray.Count -gt 0) {
        $Message = Get-Random -InputObject $phraseArray
    } else {
        $Message = "Claude needs your attention"
    }
}

# Ensure PSModulePath includes user modules
$userModulePath = Join-Path $env:USERPROFILE "Documents\WindowsPowerShell\Modules"
if ($env:PSModulePath -notlike "*$userModulePath*") {
    $env:PSModulePath = "$userModulePath;$env:PSModulePath"
}

try {
    Import-Module BurntToast -ErrorAction Stop

    $btShortcut = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\BurntToast.lnk"
    if (-not (Test-Path $btShortcut)) {
        New-BTShortcut -AppId "BurntToast" -ErrorAction Stop | Out-Null
    }

    if ($imageExists) {
        New-BurntToastNotification -Text $Title, $Message -AppLogo $ImagePath
    } else {
        New-BurntToastNotification -Text $Title, $Message
    }

    exit 0
} catch {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show($Message, $Title) | Out-Null
        exit 0
    } catch {
        exit 1
    }
}
