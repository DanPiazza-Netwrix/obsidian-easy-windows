#Requires -Version 5.1
<#
.SYNOPSIS
    Sets up Windows Task Scheduler to run note-sorter every 5 minutes.

.DESCRIPTION
    Creates a scheduled task that runs the note-sorter PowerShell script
    every 5 minutes in the background. Requires administrator privileges.

.PARAMETER ScriptPath
    Path to note-sorter.ps1. Defaults to $env:APPDATA\note-sorter\note-sorter.ps1

.PARAMETER TaskName
    Name of the scheduled task. Defaults to "Note Sorter"

.PARAMETER Interval
    Interval in minutes. Defaults to 5

.PARAMETER Remove
    If specified, removes the scheduled task instead of creating it.

.EXAMPLE
    # Create the scheduled task (requires admin)
    .\Setup-NotesorterSchedule.ps1

    # Remove the scheduled task
    .\Setup-NotesorterSchedule.ps1 -Remove

    # Create with custom script path
    .\Setup-NotesorterSchedule.ps1 -ScriptPath "C:\path\to\note-sorter.ps1"
#>

param(
    [string]$ScriptPath = "$env:APPDATA\note-sorter\note-sorter.ps1",
    [string]$TaskName = "Note Sorter",
    [int]$Interval = 5,
    [switch]$Remove
)

# ============================================================================
# Admin Check
# ============================================================================

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ============================================================================
# Task Management
# ============================================================================

function Remove-NotesorterTask {
    param([string]$Name)
    
    Write-Host "Removing scheduled task: $Name"
    
    try {
        $task = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
        if ($task) {
            Unregister-ScheduledTask -TaskName $Name -Confirm:$false
            Write-Host "✓ Task removed successfully"
            return $true
        }
        else {
            Write-Host "✗ Task not found"
            return $false
        }
    }
    catch {
        Write-Error "Failed to remove task: $_"
        return $false
    }
}

function Create-NotesorterTask {
    param(
        [string]$ScriptPath,
        [string]$TaskName,
        [int]$Interval
    )
    
    # Validate script exists
    if (-not (Test-Path $ScriptPath)) {
        Write-Error "Script not found: $ScriptPath"
        return $false
    }
    
    Write-Host "Creating scheduled task: $TaskName"
    Write-Host "Script: $ScriptPath"
    Write-Host "Interval: $Interval minutes"
    
    try {
        # Remove existing task if it exists
        $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($existingTask) {
            Write-Host "Removing existing task..."
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        }
        
        # Create trigger (repeat every N minutes)
        $trigger = New-ScheduledTaskTrigger `
            -Once `
            -At (Get-Date) `
            -RepetitionInterval (New-TimeSpan -Minutes $Interval) `
            -RepetitionDuration (New-TimeSpan -Days 365)
        
        # Create action (run PowerShell script)
        $action = New-ScheduledTaskAction `
            -Execute "powershell.exe" `
            -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
        
        # Create settings
        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -RunOnlyIfNetworkAvailable `
            -MultipleInstances IgnoreNew
        
        # Register the task
        Register-ScheduledTask `
            -TaskName $TaskName `
            -Trigger $trigger `
            -Action $action `
            -Settings $settings `
            -Description "Automatically files notes from drop folder into Obsidian vault" `
            -Force | Out-Null
        
        Write-Host "✓ Task created successfully"
        Write-Host ""
        Write-Host "Task Details:"
        Write-Host "  Name: $TaskName"
        Write-Host "  Interval: Every $Interval minutes"
        Write-Host "  Status: Ready"
        Write-Host ""
        Write-Host "The task will start running immediately and continue in the background."
        Write-Host "To view or modify the task, open Task Scheduler and look under:"
        Write-Host "  Task Scheduler Library > Microsoft > Windows > PowerShell > Scheduled Jobs"
        
        return $true
    }
    catch {
        Write-Error "Failed to create task: $_"
        return $false
    }
}

# ============================================================================
# Main
# ============================================================================

function Main {
    # Check for administrator privileges
    if (-not (Test-Administrator)) {
        Write-Error "This script requires administrator privileges."
        Write-Host ""
        Write-Host "Please run PowerShell as Administrator and try again:"
        Write-Host "  1. Right-click PowerShell"
        Write-Host "  2. Select 'Run as administrator'"
        Write-Host "  3. Run this script again"
        return 1
    }
    
    if ($Remove) {
        $success = Remove-NotesorterTask $TaskName
        return $success ? 0 : 1
    }
    else {
        $success = Create-NotesorterTask $ScriptPath $TaskName $Interval
        return $success ? 0 : 1
    }
}

# Run main
exit (Main)
