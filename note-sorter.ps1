#Requires -Version 5.1
<#
.SYNOPSIS
    Obsidian Note Sorter for Windows — watches drop folder and files notes into the vault.

.DESCRIPTION
    Monitors a drop folder for new markdown notes, analyzes them with Claude AI,
    and automatically files them into the correct location in an Obsidian vault
    with wikilinks and metadata.

.PARAMETER ConfigPath
    Path to config.json. Defaults to $env:APPDATA\note-sorter\config.json

.PARAMETER DryRun
    If specified, logs actions without modifying the vault.

.EXAMPLE
    .\note-sorter.ps1
    .\note-sorter.ps1 -DryRun
#>

param(
    [string]$ConfigPath = "$env:APPDATA\note-sorter\config.json",
    [switch]$DryRun
)

# ============================================================================
# Configuration & Defaults
# ============================================================================

$DEFAULTS = @{
    vault_path                    = ""
    drop_dir                      = "$env:USERPROFILE\obsidian-drop"
    filed_dir                     = "$env:USERPROFILE\obsidian-drop\Filed"
    config_dir                    = "$env:APPDATA\note-sorter"
    model                         = "claude-sonnet-4-20250514"
    max_output_tokens             = 1024
    api_key_env                   = "ANTHROPIC_API_KEY"
    connectivity_timeout_seconds  = 5
    file_settle_seconds           = 5
    log_level                     = "INFO"
    excluded_dirs                 = @(".trash", ".obsidian", "templates", ".space")
    editor                        = "notepad"
    dry_run                       = $false
}

$SYSTEM_PROMPT = @"
You are a personal knowledge management assistant. You help file notes into an Obsidian vault organized using the PARA method (Projects, Areas, Resources, Archive).

You will receive:
1. The user's filing preferences (how they like things organized)
2. An index of all existing notes in the vault (name and folder path)
3. A new note to be filed

Your job is to analyze the note and return a JSON decision with these fields:
- "action": either "new" (create as a new note) or "append" (add to an existing note)
- "reasoning": 1-2 sentences explaining your decision
- "folder": the destination folder path relative to vault root (for "new" action only)
- "filename": the filename to use WITHOUT .md extension (for "new" action only)
- "target_note": the exact name of the existing note to append to (for "append" action only)
- "wikilinks": array of existing note names that are semantically related to this content
- "suggested_tags": array of tags to add to frontmatter (use the vault's existing tag style)

Rules:
- Only suggest "append" if the new content is clearly a continuation or addition to a specific existing note. When in doubt, create a new note.
- For the folder, use existing folder paths from the vault index. Do not invent new folders.
- For wikilinks, only suggest notes that actually exist in the index. Focus on semantic relevance, not just keyword matching.
- Limit wikilinks to the 5-8 most relevant. Do not over-link.
- Return ONLY valid JSON. No markdown code fences. No commentary outside the JSON.
"@

# ============================================================================
# Logging Setup
# ============================================================================

function Setup-Logging {
    param([hashtable]$Config)
    
    $logDir = $Config.config_dir
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    $script:LogPath = Join-Path $logDir "note-sorter.log"
    $script:LogLevel = $Config.log_level
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp $($Level.PadRight(5)) $Message"
    
    # Write to console
    Write-Host $logEntry
    
    # Write to file
    if ($script:LogPath) {
        Add-Content -Path $script:LogPath -Value $logEntry
    }
}

# ============================================================================
# Configuration Loading
# ============================================================================

function Load-Config {
    param([string]$Path)
    
    $config = $DEFAULTS.Clone()
    
    if (Test-Path $Path) {
        try {
            $userConfig = Get-Content $Path | ConvertFrom-Json
            foreach ($key in $userConfig.PSObject.Properties.Name) {
                $config[$key] = $userConfig.$key
            }
        }
        catch {
            Write-Log "Error loading config: $_" "ERROR"
            return $null
        }
    }
    
    # Expand environment variables in paths
    foreach ($key in @("vault_path", "drop_dir", "filed_dir", "config_dir")) {
        if ($config[$key]) {
            $config[$key] = [System.Environment]::ExpandEnvironmentVariables($config[$key])
        }
    }
    
    return $config
}

function Load-EnvFile {
    param([string]$ConfigDir)
    
    $envPath = Join-Path $ConfigDir ".env"
    if (-not (Test-Path $envPath)) {
        return
    }
    
    Get-Content $envPath | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $key, $value = $line -split "=", 2
            $key = $key.Trim()
            $value = $value.Trim().Trim('"', "'")
            if ($key -and -not [Environment]::GetEnvironmentVariable($key)) {
                [Environment]::SetEnvironmentVariable($key, $value, "Process")
            }
        }
    }
}

# ============================================================================
# Connectivity Check
# ============================================================================

function Test-Connectivity {
    param([int]$TimeoutSeconds = 5)
    
    # For now, assume connectivity is available
    # The actual API call will fail if there's no internet
    # This avoids false negatives from connectivity checks
    return $true
}

# ============================================================================
# Vault Indexing
# ============================================================================

function Build-VaultIndex {
    param(
        [string]$VaultPath,
        [string]$CachePath,
        [string[]]$ExcludedDirs
    )
    
    $notes = @()
    $excluded = @($ExcludedDirs) + @(".git", ".obsidian")
    
    Get-ChildItem -Path $VaultPath -Filter "*.md" -Recurse | ForEach-Object {
        $relativePath = $_.FullName.Substring($VaultPath.Length + 1)
        $parts = $relativePath -split [regex]::Escape([System.IO.Path]::DirectorySeparatorChar)
        
        # Skip excluded directories
        $skip = $false
        foreach ($part in $parts[0..($parts.Length - 2)]) {
            if ($part.StartsWith(".") -or $part -in $excluded) {
                $skip = $true
                break
            }
        }
        
        if (-not $skip) {
            $notes += @{
                name = $_.BaseName
                path = $relativePath
            }
        }
    }
    
    # Check cache
    $notesJson = $notes | ConvertTo-Json -Compress
    $currentHash = (Get-FileHash -InputStream ([System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($notesJson))) -Algorithm SHA256).Hash
    
    if (Test-Path $CachePath) {
        try {
            $cached = Get-Content $CachePath | ConvertFrom-Json
            if ($cached.hash -eq $currentHash) {
                Write-Log "Vault index unchanged ($($notes.Count) notes)" "DEBUG"
                return $cached.notes
            }
        }
        catch {
            # Cache is invalid, rebuild
        }
    }
    
    # Write new cache
    $cacheDir = Split-Path $CachePath
    if (-not (Test-Path $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }
    
    $cacheData = @{
        hash    = $currentHash
        updated = (Get-Date -Format "o")
        notes   = $notes
    }
    
    $cacheData | ConvertTo-Json | Set-Content $CachePath
    Write-Log "Vault index rebuilt: $($notes.Count) notes"
    
    return $notes
}

function Format-IndexForPrompt {
    param([object[]]$Notes)
    
    return ($Notes | ForEach-Object { "$($_.name) | $($_.path)" }) -join "`n"
}

# ============================================================================
# Filing Preferences
# ============================================================================

function Load-FilingPrompt {
    param([string]$ConfigDir)
    
    $path = Join-Path $ConfigDir "filing-prompt.md"
    if (Test-Path $path) {
        return Get-Content $path -Raw
    }
    return "(No filing preferences configured.)"
}

# ============================================================================
# Drop Folder Scanning
# ============================================================================

function Get-DropFiles {
    param(
        [string]$DropDir,
        [string]$FiledDir,
        [int]$SettleSeconds
    )
    
    if (-not (Test-Path $DropDir)) {
        return @()
    }
    
    $now = Get-Date
    $files = @()
    
    Get-ChildItem -Path $DropDir -Filter "*.md" -File | Sort-Object LastWriteTime | ForEach-Object {
        # Skip files in Filed subdirectory
        if ($_.Directory.FullName -eq $FiledDir) {
            return
        }
        
        # Skip recently modified files
        $age = ($now - $_.LastWriteTime).TotalSeconds
        if ($age -lt $SettleSeconds) {
            return
        }
        
        $files += $_
    }
    
    return $files
}

# ============================================================================
# Claude API Interaction
# ============================================================================

function Invoke-ClaudeAnalysis {
    param(
        [string]$NoteContent,
        [string]$NoteFilename,
        [string]$VaultIndexText,
        [string]$FilingPrompt,
        [string]$Model,
        [int]$MaxTokens,
        [string]$ApiKey
    )
    
    $userMessage = @"
## My Filing Preferences

$FilingPrompt

## Vault Index

$VaultIndexText

## Note to File

Filename: $NoteFilename

$NoteContent
"@
    
    Write-Log "Sending to Claude: $($userMessage.Length) chars" "DEBUG"
    
    $body = @{
        model       = $Model
        max_tokens  = $MaxTokens
        system      = $SYSTEM_PROMPT
        messages    = @(
            @{
                role    = "user"
                content = $userMessage
            }
        )
    } | ConvertTo-Json -Depth 10
    
    $headers = @{
        "x-api-key"       = $ApiKey
        "anthropic-version" = "2023-06-01"
        "Content-Type"    = "application/json"
    }
    
    try {
        $response = Invoke-RestMethod -Uri "https://api.anthropic.com/v1/messages" `
            -Method Post `
            -Headers $headers `
            -Body $body `
            -TimeoutSec 30
        
        $text = $response.content[0].text.Trim()
        return Parse-ClaudeResponse $text
    }
    catch {
        Write-Log "Claude API error: $_" "ERROR"
        return $null
    }
}

function Parse-ClaudeResponse {
    param([string]$Text)
    
    # Remove markdown code fences if present
    $text = $text -replace '```json\s*', '' -replace '```\s*$', ''
    
    try {
        return $text | ConvertFrom-Json
    }
    catch {
        Write-Log "Failed to parse Claude response: $_" "ERROR"
        return $null
    }
}

# ============================================================================
# Decision Validation
# ============================================================================

function Validate-Decision {
    param(
        [object]$Decision,
        [string]$VaultPath,
        [object[]]$Notes
    )
    
    if (-not $Decision) {
        return $null
    }
    
    $noteNames = @($Notes | ForEach-Object { $_.name })
    $notePaths = @{}
    $Notes | ForEach-Object { $notePaths[$_.name] = $_.path }
    
    $action = if ($Decision.action) { $Decision.action } else { "new" }
    if ($action -notin @("new", "append")) {
        Write-Log "Invalid action '$action', defaulting to 'new'" "WARNING"
        $action = "new"
    }
    
    if ($action -eq "append") {
        $target = if ($Decision.target_note) { $Decision.target_note } else { "" }
        if ($target -notin $noteNames) {
            Write-Log "Append target '$target' not found, switching to 'new'" "WARNING"
            $action = "new"
        }
        else {
            $Decision | Add-Member -NotePropertyName "target_path" -NotePropertyValue $notePaths[$target] -Force
        }
    }
    
    if ($action -eq "new") {
        $folder = if ($Decision.folder) { $Decision.folder } else { "Inbox" }
        $dest = Join-Path $VaultPath $folder
        
        if (-not (Test-Path $dest)) {
            Write-Log "Folder '$folder' does not exist, falling back to Inbox" "WARNING"
            $Decision | Add-Member -NotePropertyName "folder" -NotePropertyValue "Inbox" -Force
            $dest = Join-Path $VaultPath "Inbox"
            New-Item -ItemType Directory -Path $dest -Force | Out-Null
        }
        
        $filename = if ($Decision.filename) { $Decision.filename } else { "Untitled" }
        # Sanitize filename
        $filename = $filename -replace '[<>:"/\\|?*]', ''
        if (-not $filename) {
            $filename = "Untitled"
        }
        $Decision | Add-Member -NotePropertyName "filename" -NotePropertyValue $filename -Force
    }
    
    $Decision | Add-Member -NotePropertyName "action" -NotePropertyValue $action -Force
    
    # Validate wikilinks
    $rawLinks = if ($Decision.wikilinks) { $Decision.wikilinks } else { @() }
    $validLinks = @($rawLinks | Where-Object { $_ -in $noteNames })
    $dropped = @($rawLinks | Where-Object { $_ -notin $noteNames })
    
    if ($dropped.Count -gt 0) {
        Write-Log "Dropped non-existent wikilinks: $($dropped -join ', ')" "DEBUG"
    }
    
    $Decision | Add-Member -NotePropertyName "wikilinks" -NotePropertyValue $validLinks -Force
    
    return $Decision
}

# ============================================================================
# Content Transformation
# ============================================================================

function Insert-Wikilinks {
    param(
        [string]$Content,
        [string[]]$Links
    )
    
    if (-not $Links -or $Links.Count -eq 0) {
        return $Content
    }
    
    $related = "`n`n## Related`n`n"
    $related += ($Links | ForEach-Object { "- [[$_]]" }) -join "`n"
    
    return $Content.TrimEnd() + $related + "`n"
}

function Build-Frontmatter {
    param(
        [string]$Filename,
        [string[]]$Tags
    )
    
    $now = Get-Date -Format "yyyy-MM-dd HH:mm"
    $lines = @(
        "---",
        "created: $now",
        "modified: $now",
        "filed_by: note-sorter"
    )
    
    if ($Tags -and $Tags.Count -gt 0) {
        $tagStr = $Tags -join ", "
        $lines += "tags: $tagStr"
    }
    
    $lines += "---"
    return $lines -join "`n"
}

function Strip-ExistingFrontmatter {
    param([string]$Content)
    
    if (-not $Content.StartsWith("---")) {
        return @($null, $Content)
    }
    
    $parts = $Content -split "---", 3
    if ($parts.Count -lt 3) {
        return @($null, $Content)
    }
    
    return @($null, $parts[2].TrimStart("`n"))
}

# ============================================================================
# Filing Execution
# ============================================================================

function Execute-Filing {
    param(
        [object]$Decision,
        [System.IO.FileInfo]$NotePath,
        [string]$NoteContent,
        [string]$VaultPath,
        [string]$FiledDir,
        [bool]$DryRun
    )
    
    $vault = $VaultPath
    $now = Get-Date
    
    # Prepare content with wikilinks
    $_, $body = Strip-ExistingFrontmatter $NoteContent
    $bodyWithLinks = Insert-Wikilinks $body $Decision.wikilinks
    
    if ($Decision.action -eq "new") {
        $folder = $Decision.folder
        $filename = $Decision.filename
        $dest = Join-Path $vault $folder "$filename.md"
        
        # Avoid overwriting
        if (Test-Path $dest) {
            $counter = 1
            while (Test-Path $dest) {
                $dest = Join-Path $vault $folder "$filename $counter.md"
                $counter++
            }
            Write-Log "Filename collision, using: $(Split-Path $dest -Leaf)"
        }
        
        $tags = $Decision.suggested_tags
        if (-not $tags) { $tags = @() }
        $frontmatter = Build-Frontmatter $filename $tags
        $fullContent = $frontmatter + "`n`n" + $bodyWithLinks
        
        if ($DryRun) {
            Write-Log "[DRY RUN] Would create: $dest"
            Write-Log "[DRY RUN] Reasoning: $($Decision.reasoning)"
            return $null
        }
        
        $destDir = Split-Path $dest
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        
        Set-Content -Path $dest -Value $fullContent
        Write-Log "Created: $(Resolve-Path $dest -Relative)"
    }
    elseif ($Decision.action -eq "append") {
        $targetPath = Join-Path $vault $Decision.target_path
        
        if (-not (Test-Path $targetPath)) {
            Write-Log "Append target missing: $targetPath" "ERROR"
            return $null
        }
        
        $timeStr = $now.ToString("yyyy-MM-dd 'at' hh:mm tt")
        $appendBlock = "`n`n---`n`n*Added by Note Sorter on $timeStr*`n`n$bodyWithLinks"
        
        if ($DryRun) {
            Write-Log "[DRY RUN] Would append to: $targetPath"
            Write-Log "[DRY RUN] Reasoning: $($Decision.reasoning)"
            return $null
        }
        
        Add-Content -Path $targetPath -Value $appendBlock
        Write-Log "Appended to: $($Decision.target_path)"
    }
    
    # Move original to Filed/
    if (-not (Test-Path $FiledDir)) {
        New-Item -ItemType Directory -Path $FiledDir -Force | Out-Null
    }
    
    $timestampPrefix = $now.ToString("yyyyMMdd-HHmmss")
    $filedName = "${timestampPrefix}_$($NotePath.Name)"
    $filedDest = Join-Path $FiledDir $filedName
    
    if (-not $DryRun) {
        Move-Item -Path $NotePath.FullName -Destination $filedDest -Force
        Write-Log "Moved original to: Filed/$filedName"
    }
    
    return $filedDest
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
    
    if (-not $config.vault_path) {
        Write-Error "Error: vault_path not set in config.json"
        return 1
    }
    
    # Setup logging
    Setup-Logging $config
    
    # Load .env fallback
    Load-EnvFile $config.config_dir
    
    # Get API key
    $apiKey = [Environment]::GetEnvironmentVariable($config.api_key_env)
    if (-not $apiKey) {
        Write-Log "API key not found in env var '$($config.api_key_env)' or .env file" "ERROR"
        return 1
    }
    
    # Check connectivity
    if (-not (Test-Connectivity $config.connectivity_timeout_seconds)) {
        Write-Log "Offline — skipping this run. Files will be processed next time."
        return 0
    }
    
    # Build vault index
    $cachePath = Join-Path $config.config_dir "vault-index.json"
    $notes = Build-VaultIndex $config.vault_path $cachePath $config.excluded_dirs
    $vaultIndexText = Format-IndexForPrompt $notes
    
    # Load filing preferences
    $filingPrompt = Load-FilingPrompt $config.config_dir
    
    # Get files to process
    $files = Get-DropFiles $config.drop_dir $config.filed_dir $config.file_settle_seconds
    
    if ($files.Count -eq 0) {
        Write-Log "No files to process" "DEBUG"
        return 0
    }
    
    Write-Log "Processing $($files.Count) file(s)"
    
    # Process each file
    foreach ($file in $files) {
        Write-Log "Analyzing: $($file.Name)"
        
        $noteContent = Get-Content $file.FullName -Raw
        $decision = Invoke-ClaudeAnalysis `
            -NoteContent $noteContent `
            -NoteFilename $file.Name `
            -VaultIndexText $vaultIndexText `
            -FilingPrompt $filingPrompt `
            -Model $config.model `
            -MaxTokens $config.max_output_tokens `
            -ApiKey $apiKey
        
        if (-not $decision) {
            Write-Log "Failed to get decision for $($file.Name)" "ERROR"
            continue
        }
        
        $decision = Validate-Decision $decision $config.vault_path $notes
        if (-not $decision) {
            Write-Log "Failed to validate decision for $($file.Name)" "ERROR"
            continue
        }
        
        Write-Log "Decision: $($decision.action) — $($decision.reasoning)"
        
        $dryRunFlag = $DryRun -or $config.dry_run
        Execute-Filing $decision $file $noteContent $config.vault_path $config.filed_dir $dryRunFlag
    }
    
    return 0
}

# Run main
exit (Main)
