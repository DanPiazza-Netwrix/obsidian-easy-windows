#Requires -Version 5.1
<#
.SYNOPSIS
    Creates desktop shortcuts for Note Sorter and Note Capture scripts.

.DESCRIPTION
    Creates convenient desktop shortcuts to run the note-sorter and note-capture
    scripts without needing to open PowerShell manually.

.EXAMPLE
    .\Create-DesktopShortcuts.ps1
#>

# Get desktop path
$desktopPath = [System.IO.Path]::Combine($env:USERPROFILE, "Desktop")

# Verify desktop exists
if (-not (Test-Path $desktopPath)) {
    Write-Error "Desktop folder not found at: $desktopPath"
    exit 1
}

# Create COM object for shortcuts
$shell = New-Object -ComObject WScript.Shell

# ============================================================================
# Create Note Sorter Shortcut
# ============================================================================

$sorterShortcutPath = Join-Path $desktopPath "Note Sorter.lnk"
$sorterScript = "$env:APPDATA\note-sorter\note-sorter.ps1"

# Verify script exists
if (-not (Test-Path $sorterScript)) {
    Write-Error "note-sorter.ps1 not found at: $sorterScript"
    Write-Host "Please copy note-sorter.ps1 to $env:APPDATA\note-sorter\ first"
    exit 1
}

$sorterShortcut = $shell.CreateShortcut($sorterShortcutPath)
$sorterShortcut.TargetPath = "powershell.exe"
$sorterShortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$sorterScript`""
$sorterShortcut.WorkingDirectory = "$env:APPDATA\note-sorter"
$sorterShortcut.Description = "Run Note Sorter to file notes into your Obsidian vault"
$sorterShortcut.WindowStyle = 1  # Normal window
$sorterShortcut.Save()

Write-Host "✓ Created: Note Sorter.lnk on Desktop"

# ============================================================================
# Create Note Capture Shortcut
# ============================================================================

$captureShortcutPath = Join-Path $desktopPath "Note Capture.lnk"
$captureScript = "$env:APPDATA\note-sorter\note-capture.ps1"

# Verify script exists
if (-not (Test-Path $captureScript)) {
    Write-Error "note-capture.ps1 not found at: $captureScript"
    Write-Host "Please copy note-capture.ps1 to $env:APPDATA\note-sorter\ first"
    exit 1
}

$captureShortcut = $shell.CreateShortcut($captureShortcutPath)
$captureShortcut.TargetPath = "powershell.exe"
$captureShortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$captureScript`""
$captureShortcut.WorkingDirectory = "$env:APPDATA\note-sorter"
$captureShortcut.Description = "Quick capture a new note"
$captureShortcut.WindowStyle = 1  # Normal window
$captureShortcut.Save()

Write-Host "✓ Created: Note Capture.lnk on Desktop"

# ============================================================================
# Summary
# ============================================================================

Write-Host ""
Write-Host "Desktop shortcuts created successfully!"
Write-Host ""
Write-Host "You now have two shortcuts on your desktop:"
Write-Host "  • Note Sorter.lnk  - Run this to file notes into your vault"
Write-Host "  • Note Capture.lnk - Run this to quickly capture a new note"
Write-Host ""
Write-Host "You can:"
Write-Host "  • Double-click them to run"
Write-Host "  • Right-click and pin to Start menu or taskbar"
Write-Host "  • Drag them to your taskbar for quick access"
