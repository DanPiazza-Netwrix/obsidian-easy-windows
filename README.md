# Obsidian Easy

A smart note-filing system for [Obsidian](https://obsidian.md). Drop markdown notes into a folder, and they automatically get filed into the right place in your vault with internal wikilinks added.

Powered by the Claude API for intelligent routing decisions.

## How It Works

1. **Capture**: Click the Note Capture app (or run `note-capture` from the terminal). A new markdown file opens in your editor.
2. **Write**: Jot down your note, save, and close.
3. **Auto-file**: A background job picks up the note every few minutes, analyzes it with Claude, and:
   - Files it into the correct folder in your Obsidian vault (or appends it to an existing note)
   - Adds `[[wikilinks]]` to semantically related notes
   - Adds YAML frontmatter (`created`, `modified`, `filed_by`)
4. **Backup**: The original file is moved to a `Filed/` subfolder as a backup.

## Features

- **Smart routing** — Claude analyzes your note content and your filing preferences to decide where each note belongs
- **Wikilink detection** — Automatically links to related people, projects, and topics in your vault
- **Offline resilience** — If there's no internet, the script exits gracefully and retries on the next run
- **Configurable editor** — Use Sublime Text, VS Code, vim, or any editor you prefer
- **Dry-run mode** — Test what the sorter would do without touching your vault
- **Editable filing preferences** — A plain markdown file describes how you like things organized
- **Automatic scheduling** — Runs every 5 minutes via macOS launchd, or immediately when a new file appears

## Requirements

- **macOS** (uses launchd for scheduling; adaptable to Linux with cron/systemd)
- **Python 3.12+**
- **[uv](https://docs.astral.sh/uv/)** — Python package manager (handles dependencies automatically)
- **[Anthropic API key](https://console.anthropic.com/)** — for Claude API access
- **jq** — for the capture script to read config (`brew install jq`)

## Installation

### 1. Clone this repo

```bash
git clone https://github.com/gman247/obsidian-easy.git
cd obsidian-easy
```

### 2. Create directories

```bash
mkdir -p ~/.config/note-sorter ~/obsidian-drop/Filed ~/.local/bin
```

### 3. Install the scripts

```bash
cp note-sorter ~/.local/bin/note-sorter
cp note-capture ~/.local/bin/note-capture
chmod +x ~/.local/bin/note-sorter ~/.local/bin/note-capture
```

### 4. Configure

```bash
# Create your config from the example
cp config.example.json ~/.config/note-sorter/config.json

# Edit it — set your vault_path and editor at minimum
nano ~/.config/note-sorter/config.json

# Copy the filing preferences (edit to match your vault structure)
cp filing-prompt.md ~/.config/note-sorter/filing-prompt.md
```

### 5. Set your API key

```bash
# Option A: Add to your .env file (recommended for launchd)
echo "ANTHROPIC_API_KEY=sk-ant-..." > ~/.config/note-sorter/.env

# Option B: Export in your shell profile
echo 'export ANTHROPIC_API_KEY="sk-ant-..."' >> ~/.zprofile
```

### 6. Test it

```bash
# Create a test note
echo "# Test note about strategy and planning" > ~/obsidian-drop/test.md

# Wait a few seconds for the settle time, then run
sleep 6 && ~/.local/bin/note-sorter

# Check the log
cat ~/.config/note-sorter/note-sorter.log
```

Start with `"dry_run": true` in your config to see what the sorter would do without making changes.

### 7. Set up the scheduled job

Edit `com.note-sorter.plist` and replace all instances of `YOUR_USERNAME` with your macOS username, then:

```bash
cp com.note-sorter.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.note-sorter.plist

# Verify it's loaded
launchctl list | grep note-sorter
```

### 8. Create the Dock shortcut (optional)

Create a macOS app that calls `note-capture` for one-click capture:

```bash
osacompile -o ~/Applications/"Note Capture.app" -e '
do shell script "~/.local/bin/note-capture"'
```

Then drag `Note Capture.app` from `~/Applications/` to your Dock.

## Configuration

### config.json

| Field | Description | Default |
|-------|-------------|---------|
| `vault_path` | Absolute path to your Obsidian vault | *(required)* |
| `drop_dir` | Folder to watch for new notes | `~/obsidian-drop` |
| `filed_dir` | Where processed originals are backed up | `~/obsidian-drop/Filed` |
| `config_dir` | Where config/logs/cache live | `~/.config/note-sorter` |
| `model` | Claude model to use | `claude-sonnet-4-20250514` |
| `max_output_tokens` | Max tokens for Claude response | `1024` |
| `api_key_env` | Environment variable name for API key | `ANTHROPIC_API_KEY` |
| `connectivity_timeout_seconds` | Timeout for API reachability check | `5` |
| `file_settle_seconds` | Skip files modified less than N seconds ago | `5` |
| `log_level` | Logging verbosity (`DEBUG`, `INFO`, `WARNING`, `ERROR`) | `INFO` |
| `excluded_dirs` | Vault directories to exclude from indexing | `[".trash", ".obsidian", "templates", ".space"]` |
| `editor` | Command to open markdown files for editing | `open -t` (macOS TextEdit) |
| `dry_run` | Log actions without modifying the vault | `false` |

### Editor examples

| Editor | `editor` value |
|--------|---------------|
| Sublime Text | `"/Applications/Sublime Text.app/Contents/SharedSupport/bin/subl"` |
| VS Code | `"code"` |
| Vim | `"vim"` |
| TextEdit (macOS) | `"open -t"` |

### filing-prompt.md

This is your voice telling Claude how you organize things. Edit it to match your vault structure, folder conventions, and preferences. The contents are injected into every Claude API call.

## File Structure

```
~/.config/note-sorter/
    config.json              # Your configuration
    filing-prompt.md         # Your filing preferences
    .env                     # API key (not committed to git)
    vault-index.json         # Auto-generated cache
    note-sorter.log          # Activity log

~/.local/bin/
    note-sorter              # Main script
    note-capture             # Quick-capture script

~/obsidian-drop/             # Drop folder
    Filed/                   # Backups of processed files

~/Library/LaunchAgents/
    com.note-sorter.plist    # Scheduled job
```

## Logs

All activity is logged to `~/.config/note-sorter/note-sorter.log`:

```
2026-02-14 11:51:55 INFO  Processing 1 file(s)
2026-02-14 11:51:55 INFO  Analyzing: security-thoughts.md
2026-02-14 11:52:01 INFO  Decision: new — Strategic note about data security
2026-02-14 11:52:01 INFO  Created: 030. Resources/Strategy/Data Security Strategy.md
2026-02-14 11:52:01 INFO  Moved original to: Filed/20260214-115201_security-thoughts.md
```

Set `"log_level": "DEBUG"` to see full Claude API decisions including wikilinks and tags.

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

## License

MIT
