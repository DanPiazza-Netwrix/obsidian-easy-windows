# Obsidian Easy for Windows

A smart note-filing system for [Obsidian](https://obsidian.md) on Windows. Drop markdown notes into a folder, and they automatically get filed into the right place in your vault with internal wikilinks added.

Powered by the Claude API for intelligent routing decisions.

> **Note**: This is the Windows-only version using PowerShell. For the original macOS/Python version, see [obsidian-easy](https://github.com/gman247/obsidian-easy).

## How It Works

1. **Create**: Create a markdown (`.md`) or text (`.txt`) file in your drop folder (e.g., `C:\Users\YourName\obsidian-drop\my-note.md`)
2. **Write**: Add your note content and save the file.
3. **File**: Run `note-sorter.ps1` to analyze the note with Claude and:
   - File it into the correct folder in your Obsidian vault (or append it to an existing note)
   - Add `[[wikilinks]]` to semantically related notes
   - Add YAML frontmatter (`created`, `modified`, `filed_by`)
4. **Backup**: The original file is moved to a `Filed\` subfolder as a backup.

**Optional**: Set up a Windows Task Scheduler job to run `note-sorter.ps1` automatically every 5 minutes.

**Note**: Text files (`.txt`) are automatically converted to markdown format with a heading based on the filename.

## Requirements

- **Windows 10 or later** (with PowerShell 5.1+, included by default)
- **[Anthropic API key](https://console.anthropic.com/)** — for Claude API access
- **Administrator privileges** — to set up the scheduled task

## Installation

### 1. Clone or download this repository

```powershell
git clone https://github.com/DanPiazza-Netwrix/obsidian-easy-windows.git
cd obsidian-easy-windows
```

### 2. Create directories

```powershell
# Create config and drop directories
New-Item -ItemType Directory -Path "$env:APPDATA\note-sorter" -Force
New-Item -ItemType Directory -Path "$env:USERPROFILE\obsidian-drop\Filed" -Force
```

### 3. Copy scripts to a convenient location

```powershell
# Option A: Copy to AppData (recommended)
Copy-Item note-sorter.ps1 -Destination "$env:APPDATA\note-sorter\"
Copy-Item Setup-NotesorterSchedule.ps1 -Destination "$env:APPDATA\note-sorter\"

# Option B: Copy to a custom location (e.g., C:\Tools\note-sorter)
New-Item -ItemType Directory -Path "C:\Tools\note-sorter" -Force
Copy-Item note-sorter.ps1, Setup-NotesorterSchedule.ps1 -Destination "C:\Tools\note-sorter\"
```

### 4. Configure

```powershell
# Copy the example config
Copy-Item config.example.json -Destination "$env:APPDATA\note-sorter\config.json"

# Edit it with your favorite editor (replace notepad with your editor)
notepad "$env:APPDATA\note-sorter\config.json"
```

**Required settings:**
- `vault_path`: Absolute path to your Obsidian vault (e.g., `C:\Users\YourName\Documents\My Obsidian Vault`)
- `editor`: Your preferred editor (e.g., `code`, `notepad++`, `vim`)

**Optional settings:**
- `drop_dir`: Where to watch for new notes (default: `%USERPROFILE%\obsidian-drop`)
- `filed_dir`: Where to backup processed notes (default: `%USERPROFILE%\obsidian-drop\Filed`)
- `model`: Claude model to use (default: `claude-haiku-4-5-20251001`)
- `log_level`: Logging verbosity (`DEBUG`, `INFO`, `WARNING`, `ERROR`)

### 5. Set your API key

```powershell
# Option A: Set as environment variable (recommended)
[Environment]::SetEnvironmentVariable("ANTHROPIC_API_KEY", "sk-ant-...", "User")

# Then restart PowerShell for the change to take effect

# Option B: Create a .env file in the config directory
# This is useful for Task Scheduler context
"ANTHROPIC_API_KEY=sk-ant-..." | Set-Content "$env:APPDATA\note-sorter\.env"
```

### 6. Copy filing preferences

```powershell
Copy-Item filing-prompt.md -Destination "$env:APPDATA\note-sorter\"

# Edit to match your vault structure
notepad "$env:APPDATA\note-sorter\filing-prompt.md"
```

### 7. Test it

```powershell
# Create a test note
"# Test note about strategy and planning" | Set-Content "$env:USERPROFILE\obsidian-drop\test.md"

# Wait a few seconds for the settle time, then run
Start-Sleep -Seconds 6
& "$env:APPDATA\note-sorter\note-sorter.ps1"

# Check the log
Get-Content "$env:APPDATA\note-sorter\note-sorter.log" -Tail 20
```

Start with `"dry_run": true` in your config to see what the sorter would do without making changes.

### 8. Set up the scheduled task

**Important: This requires administrator privileges.**

```powershell
# Run PowerShell as Administrator, then:
& "$env:APPDATA\note-sorter\Setup-NotesorterSchedule.ps1"
```

This will create a Windows Task Scheduler task that runs `note-sorter.ps1` every 5 minutes.

**To verify the task was created:**
```powershell
Get-ScheduledTask -TaskName "Note Sorter"
```

**To remove the task later:**
```powershell
# Run as Administrator
& "$env:APPDATA\note-sorter\Setup-NotesorterSchedule.ps1" -Remove
```

### 9. Running the sorter

Run the sorter from PowerShell 7 to file your notes:

```powershell
# File notes into your vault
& "$env:APPDATA\note-sorter\note-sorter.ps1"

# File notes and have Claude summarize/reformat them for readability
& "$env:APPDATA\note-sorter\note-sorter.ps1" -Summarize
```

Or if you've copied it to a custom location:
```powershell
& "C:\Tools\note-sorter\note-sorter.ps1"
& "C:\Tools\note-sorter\note-sorter.ps1" -Summarize
```

**Workflow:**
1. Create a markdown file in `%USERPROFILE%\obsidian-drop\` (or your configured `drop_dir`)
2. Run the command above to file it into your vault
3. (Optional) Use `-Summarize` flag to have Claude improve readability and conciseness
4. (Optional) Set up a scheduled task to run this automatically every 5 minutes

## Configuration

### config.json

| Field | Description | Default |
|-------|-------------|---------|
| `vault_path` | Absolute path to your Obsidian vault | *(required)* |
| `drop_dir` | Folder to watch for new notes | `%USERPROFILE%\obsidian-drop` |
| `filed_dir` | Where processed originals are backed up | `%USERPROFILE%\obsidian-drop\Filed` |
| `config_dir` | Where config/logs/cache live | `%APPDATA%\note-sorter` |
| `model` | Claude model to use | `claude-haiku-4-5-20251001` |
| `max_output_tokens` | Max tokens for Claude response | `1024` |
| `api_key_env` | Environment variable name for API key | `ANTHROPIC_API_KEY` |
| `connectivity_timeout_seconds` | Timeout for API reachability check | `5` |
| `file_settle_seconds` | Skip files modified less than N seconds ago | `5` |
| `log_level` | Logging verbosity (`DEBUG`, `INFO`, `WARNING`, `ERROR`) | `INFO` |
| `excluded_dirs` | Vault directories to exclude from indexing | `[".trash", ".obsidian", "templates", ".space"]` |
| `dry_run` | Log actions without modifying the vault | `false` |

### filing-prompt.md

This is your voice telling Claude how you organize things. Edit it to match your vault structure, folder conventions, and preferences. The contents are injected into every Claude API call.

## File Structure

```
%APPDATA%\note-sorter\
    config.json              # Your configuration
    filing-prompt.md         # Your filing preferences
    .env                     # API key (optional, for Task Scheduler)
    vault-index.json         # Auto-generated cache
    note-sorter.log          # Activity log

%USERPROFILE%\obsidian-drop\
    Filed\                   # Backups of processed files
```

## Logs

All activity is logged to `%APPDATA%\note-sorter\note-sorter.log`:

```
2026-02-14 11:51:55 INFO  Processing 1 file(s)
2026-02-14 11:51:55 INFO  Analyzing: security-thoughts.md
2026-02-14 11:52:01 INFO  Decision: new — Strategic note about data security
2026-02-14 11:52:01 INFO  Created: 030. Resources\Strategy\Data Security Strategy.md
2026-02-14 11:52:01 INFO  Moved original to: Filed\20260214-115201_security-thoughts.md
```

Set `"log_level": "DEBUG"` to see full Claude API decisions including wikilinks and tags.

### Log Rotation

The log file automatically rotates when it exceeds 1 MB. The script keeps the last 10 rotated log files:
- `note-sorter.log` — Current log file
- `note-sorter.1.log` — Previous log file
- `note-sorter.2.log` — Older log file
- ... and so on up to `note-sorter.10.log`

Older logs are automatically deleted to prevent disk space issues.

## How Notes Get Filed

When Claude analyzes a note, it returns a JSON decision:

- **action**: `new` (create a new note) or `append` (add to an existing note)
- **folder**: destination folder in the vault
- **filename**: what to name the new note
- **wikilinks**: related notes to link via `[[wikilinks]]`
- **reasoning**: why it made this decision

Appended content is added with a separator:

```markdown
---

*Added by Note Sorter on 2026-02-14 at 10:35 AM*

Your appended content here...
```

## Troubleshooting

### "API key not found" error

Make sure you've set the `ANTHROPIC_API_KEY` environment variable:

```powershell
# Check if it's set
$env:ANTHROPIC_API_KEY

# If empty, set it
[Environment]::SetEnvironmentVariable("ANTHROPIC_API_KEY", "sk-ant-...", "User")

# Restart PowerShell for the change to take effect
```

Alternatively, create a `.env` file in `%APPDATA%\note-sorter\`:
```
ANTHROPIC_API_KEY=sk-ant-...
```

### "vault_path not set" error

Edit your `config.json` and make sure `vault_path` is set to the absolute path of your Obsidian vault:

```json
{
  "vault_path": "C:\\Users\\YourName\\Documents\\My Obsidian Vault",
  ...
}
```

### Task Scheduler task not running

1. Check that you ran `Setup-NotesorterSchedule.ps1` as Administrator
2. Verify the task exists:
   ```powershell
   Get-ScheduledTask -TaskName "Note Sorter"
   ```
3. Check the task's last run result in Task Scheduler:
   - Open Task Scheduler
   - Navigate to Task Scheduler Library
   - Look for "Note Sorter"
   - Check the "Last Run Result" column

### Notes not being filed

1. Check the log file: `%APPDATA%\note-sorter\note-sorter.log`
2. Make sure `dry_run` is set to `false` in your config
3. Verify your `filing-prompt.md` is configured correctly
4. Check that your vault path is correct and accessible

### Editor not opening

Make sure the `editor` value in your config is correct:

```powershell
# Test if your editor is accessible
& "code" --version  # For VS Code
& "notepad++" --version  # For Notepad++
```

If the command doesn't work, use the full path:
```json
{
  "editor": "C:\\Program Files\\Notepad++\\notepad++.exe"
}
```

## Differences from macOS version

- **Paths**: Uses Windows environment variables (`%APPDATA%`, `%USERPROFILE%`) instead of Unix-style paths (`~`, `~/.config`)
- **Scheduling**: Uses Windows Task Scheduler instead of launchd
- **Scripts**: All scripts are PowerShell instead of shell scripts
- **Configuration**: Same JSON format, but with Windows-style paths
- **API key**: Can be stored in environment variable or `.env` file (same as macOS)

## License

MIT
