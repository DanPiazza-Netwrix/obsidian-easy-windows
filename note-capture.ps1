#Requires -Version 5.1
<#
.SYNOPSIS
    Quick Capture — creates a timestamped markdown file and opens it in the configured editor.

.DESCRIPTION
    Creates a new markdown file in the drop folder with a timestamp and opens it
    in the configured editor for quick note capture.

.PARAMETER ConfigPath
    Path to config.json. Defaults to $env:APPDATA\note-sorter\config.json

.EXAMPLE
    .\note-capture.ps1
#>

param(
    [string]$ConfigPath = "$env:APPDATA\note-sorter\config.json"
)

# ============================================================================
# Configuration Loading
# ============================================================================

function Load-Config {
    param([string]$Path)
    
    $defaults = @{
        drop_dir = "$env:USERPROFILE\obsidian-drop"
        editor   = "notepad"
    }
    
    if (Test-Path $Path) {
        try {
            $config = Get-Content $Path | ConvertFrom-Json
            
            # Use user config values, fall back to defaults
            $dropDir = $config.drop_dir ?? $defaults.drop_dir
            $editor = $config.editor ?? $defaults.editor
            
            # Expand environment variables
            $dropDir = [System.Environment]::ExpandEnvironmentVariables($dropDir)
            $editor = [System.Environment]::ExpandEnvironmentVariables($editor)
            
            return @{
                drop_dir = $dropDir
                editor   = $editor
            }
        }
        catch {
            Write-Error "Error loading config: $_"
            return $null
        }
    }
    
    # Use defaults if config doesn't exist
    return @{
        drop_dir = [System.Environment]::ExpandEnvironmentVariables($defaults.drop_dir)
        editor   = $defaults.editor
    }
}

# ============================================================================
# Main
# ============================================================================

function Main {
    # Load configuration
    $config = Load-Config $ConfigPath
    if (-not $config) {
        Write-Error "Failed to load configuration"
        return 1
    }
    
    # Create drop directory if it doesn't exist
    if (-not (Test-Path $config.drop_dir)) {
        try {
            New-Item -ItemType Directory -Path $config.drop_dir -Force | Out-Null
        }
        catch {
            Write-Error "Failed to create drop directory: $_"
            return 1
        }
    }
    
    # Generate timestamp and filename
    $timestamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
    $filename = Join-Path $config.drop_dir "$timestamp.md"
    
    # Create the file with a heading placeholder
    try {
        "# `n`n" | Set-Content -Path $filename -Encoding UTF8
    }
    catch {
        Write-Error "Failed to create note file: $_"
        return 1
    }
    
    # Open in the configured editor
    try {
        # Handle different editor types
        if ($config.editor -like "*code*") {
            # VS Code
            & $config.editor $filename
        }
        elseif ($config.editor -like "*sublime*") {
            # Sublime Text
            & $config.editor $filename
        }
        elseif ($config.editor -like "*vim*" -or $config.editor -like "*nvim*") {
            # Vim/Neovim - open in new terminal
            Start-Process -FilePath $config.editor -ArgumentList $filename -NoNewWindow
        }
        else {
            # Default: try to execute as-is
            & $config.editor $filename
        }
    }
    catch {
        Write-Error "Failed to open editor: $_"
        Write-Host "Note file created at: $filename"
        Write-Host "Please open it manually in your editor."
        return 1
    }
    
    return 0
}

# Run main
exit (Main)
