# Claude Integration Guide for Obsidian Easy Windows

This document provides context for Claude and other AI systems working with this codebase. It covers the project's architecture, Claude API integration patterns, coding standards, and guidelines for AI-assisted development.

## Project Overview

### What It Does

Obsidian Easy for Windows is a smart note-filing system that automatically organizes markdown notes into an Obsidian vault using Claude AI for intelligent routing decisions.

### Core Purpose

- Monitor a drop folder for new markdown/text files
- Analyze each note with Claude API to determine optimal filing location
- File notes into the vault with automatic wikilink generation
- Add YAML frontmatter with metadata (created, modified, filed_by)
- Backup original files to a "Filed" directory
- Optionally summarize/reformat notes for improved readability

### Key Architectural Decisions

1. **PowerShell-based**: Windows-only implementation using PowerShell 5.1+ (no external dependencies)
2. **Claude-driven decisions**: All filing logic delegated to Claude API via structured JSON responses
3. **Vault indexing with caching**: Builds a searchable index of all vault notes with SHA256 hash-based cache invalidation
4. **Dry-run mode**: All changes can be previewed without modifying the vault
5. **Scheduled execution**: Integrates with Windows Task Scheduler for automated 5-minute polling
6. **User-configurable filing preferences**: `filing-prompt.md` encodes the user's organizational style and rules

## Claude API Integration

### System Prompt

The system prompt (defined in `note-sorter.ps1` lines 52-77) establishes Claude's role:

```text
You are a personal knowledge management assistant. You help file notes into an Obsidian vault 
organized using the PARA method (Projects, Areas, Resources, Archive).
```

Claude receives:

1. User's filing preferences (from `filing-prompt.md`)
2. Vault index (list of all existing notes with paths)
3. New note content and filename

### Claude Response Format

Claude returns a JSON object with these fields:

```json
{
  "action": "new" | "append",
  "reasoning": "1-2 sentence explanation",
  "folder": "destination/folder/path",           // REQUIRED for ALL actions (fallback if append target missing)
  "filename": "Note Title",                      // REQUIRED for ALL actions (fallback if append target missing, no .md extension)
  "target_note": "Existing Note Name",           // for "append" action only
  "wikilinks": ["Note 1", "Note 2"],             // existing notes to link
  "suggested_tags": ["#tag1", "#tag2"],          // tags for frontmatter
  "content": "optionally reformatted content"    // only if summarize mode enabled
}
```

### Key Constraints Claude Must Follow

1. **ALWAYS return folder and filename**: These fields are REQUIRED for ALL actions (new and append). They serve as fallback values if an append target doesn't exist.
2. **Only suggest existing folders**: Claude must use folder paths from the vault index; never invent new folders
3. **Only link existing notes**: Wikilinks must reference notes that actually exist in the vault
4. **Limit wikilinks**: Suggest 5-8 most relevant links, not exhaustive linking
5. **Append sparingly**: Only suggest "append" if content is clearly a continuation of an existing note
6. **Respect filing rules**: Honor user-defined rules in `filing-prompt.md` (e.g., never file to Readwise, templates, or journal folders)
7. **Return valid JSON only**: No markdown code fences, no commentary outside JSON

### API Call Details

- **Endpoint**: `https://api.anthropic.com/v1/messages`
- **Model**: Configurable (default: `claude-haiku-4-5-20251001`)
- **Max tokens**: Configurable (default: 1024)
- **Timeout**: 30 seconds
- **Headers**:
  - `x-api-key`: API key from environment variable or `.env` file
  - `anthropic-version`: "2023-06-01"
  - `Content-Type`: "application/json"

### Summarize Mode

When invoked with `-Summarize` flag, Claude is instructed to:

- Improve note readability and conciseness
- Use clear formatting, bullet points, and structure
- Preserve all important information
- Return reformatted content in the `content` field

## Codebase Structure

### Main Script: `note-sorter.ps1`

#### Configuration & Defaults (lines 32-50)

- Default paths, model, timeouts, log levels
- Excluded directories (`.trash`, `.obsidian`, `templates`, `.space`)

#### Logging (lines 83-149)

- Rotating log file with 1 MB size limit, keeps last 10 files
- Log levels: DEBUG, INFO, WARNING, ERROR
- Logs to both console and file

#### Configuration Loading (lines 155-202)

- Merges user config with defaults
- Expands environment variables in paths
- Loads `.env` file as fallback for API key

#### Vault Indexing (lines 221-291)

- Recursively scans vault for `.md` files
- Excludes hidden directories and configured excluded dirs
- Caches index with SHA256 hash for change detection
- Returns array of `{name, path}` objects

#### Filing Preferences (lines 297-305)

- Loads `filing-prompt.md` from config directory
- Injected into every Claude API call

#### Drop Folder Scanning (lines 311-341)

- Monitors drop folder for `.md` and `.txt` files
- Skips recently modified files (configurable settle time)
- Skips files in the "Filed" subdirectory

#### Claude Analysis (lines 347-432)

- Constructs user message with filing preferences, vault index, and note content
- Sends to Claude API with system prompt
- Parses JSON response, removing markdown code fences if present

#### Decision Validation (lines 438-504)

- Validates Claude's decision against vault state
- Ensures target folders exist (falls back to "Inbox" if not)
- Ensures append targets exist in vault (switches to "new" if missing)
- When switching from append to new, uses Claude's provided folder/filename as fallback
- Sanitizes filenames
- Validates wikilinks against vault index
- Logs dropped/invalid suggestions

#### Content Transformation (lines 510-562)

- `Insert-Wikilinks`: Appends "## Related" section with wikilinks
- `Build-Frontmatter`: Creates YAML frontmatter with created/modified timestamps and tags
- `Strip-ExistingFrontmatter`: Removes existing frontmatter before re-processing

#### Filing Execution (lines 568-673)

- Creates new notes with frontmatter + content + wikilinks
- Appends to existing notes with separator and timestamp
- Handles filename collisions with numeric suffixes
- Moves original file to "Filed" directory with timestamp prefix
- Supports dry-run mode (logs actions without modifying vault)

#### Main (lines 679-773)

- Orchestrates the entire workflow
- Loads config, sets up logging, validates API key
- Builds vault index and loads filing preferences
- Processes each drop file sequentially
- Handles errors gracefully

### Setup Script: `Setup-NotesorterSchedule.ps1`

Creates/removes Windows Task Scheduler task to run `note-sorter.ps1` every 5 minutes.

### Configuration Files

#### `config.example.json`

- Template for user configuration
- Required: `vault_path`
- Optional: all other fields use sensible defaults

#### `filing-prompt.md`

- User's organizational style and filing rules
- Injected into Claude's system context
- Should document:
  - Folder structure and naming conventions
  - Filing rules and exceptions
  - Tag style and conventions
  - Wikilink preferences

## Coding Standards

### PowerShell Style

1. **Function naming**: Use `Verb-Noun` convention (e.g., `Build-VaultIndex`, `Invoke-ClaudeAnalysis`)
2. **Parameter validation**: Use `param()` blocks with type hints
3. **Error handling**: Use try/catch for API calls and file operations
4. **Logging**: Use `Write-Log` function for all output (not `Write-Host` directly)
5. **Comments**: Use `# ============================================================================` for section headers
6. **Indentation**: 4 spaces (PowerShell standard)

### JSON Handling

1. **Parsing**: Use `ConvertFrom-Json` with error handling
2. **Generation**: Use `ConvertTo-Json -Depth 10` for nested objects
3. **Validation**: Always validate parsed JSON before using

### File Operations

1. **Path handling**: Use `Join-Path` for cross-platform compatibility
2. **Existence checks**: Use `Test-Path` before reading/writing
3. **Directory creation**: Use `New-Item -ItemType Directory -Force`
4. **Encoding**: Use UTF-8 (PowerShell default)

### API Integration

1. **Timeouts**: Always set reasonable timeouts (30 seconds for Claude API)
2. **Error messages**: Log full error details for debugging
3. **Retry logic**: Currently no retry logic; API failures are logged and skipped
4. **Rate limiting**: No explicit rate limiting; relies on Task Scheduler 5-minute intervals

## Architecture Rules

### Never Do This

1. **Invent new folders**: Claude must only suggest existing vault folders
2. **Create invalid wikilinks**: Only link to notes that exist in the vault
3. **Modify filing-prompt.md programmatically**: It's user-configurable, not auto-generated
4. **Skip validation**: Always validate Claude's decision before executing
5. **Ignore dry-run mode**: Respect the `$DryRun` flag in all file operations
6. **Hardcode paths**: Always use environment variables and config values
7. **Write Properties into notes**: Never add Obsidian Properties (YAML frontmatter properties) to notes. Keep notes clean without metadata properties.

### Always Do This

1. **Log decisions**: Every filing decision should be logged with reasoning
2. **Validate vault state**: Check that folders/notes exist before filing
3. **Handle errors gracefully**: Log errors and continue processing other files
4. **Preserve originals**: Always backup original files to "Filed" directory
5. **Use frontmatter**: Every new note gets YAML frontmatter with metadata
6. **Respect user preferences**: Honor rules in `filing-prompt.md`

## Domain-Specific Guidance

### PARA Method

The system assumes notes are organized using the PARA method:

- **010. Projects**: Active projects with clear goals and deadlines
- **020. Areas**: Ongoing areas of responsibility
- **030. Resources**: Reference material and research
- **040. Archive**: Completed or inactive items
- **Inbox**: Miscellaneous captures that don't fit elsewhere

### Filing Decision Logic

Claude should prefer:

1. **Existing notes** (append) if content is clearly a continuation
2. **Specific folders** (new) if content fits a clear category
3. **Resources** over Areas when ambiguous
4. **Fewer, relevant wikilinks** over exhaustive linking

### Special Handling

- **Text files (.txt)**: Automatically converted to markdown with filename as heading
- **Summarize mode**: Improves readability while preserving information
- **Dry-run mode**: Useful for testing filing logic without vault modifications

## AI Usage Instructions

### When to Use AI for Changes

✅ **Good candidates for AI assistance:**

- Adding new filing rules or folder structures
- Improving Claude's system prompt or decision logic
- Refactoring PowerShell functions for clarity
- Adding new configuration options
- Improving error messages and logging
- Writing documentation and comments

❌ **Not recommended for AI:**

- Changing core filing logic without understanding PARA method
- Modifying API integration without testing
- Changing file paths or directory structures without validation
- Removing validation or error handling

### PR Description Format

When AI generates changes, include:

1. **What changed**: Brief description of modifications
2. **Why**: Rationale for the change
3. **Testing**: How to verify the change works
4. **Impact**: Any side effects or breaking changes

### Testing Requirements

Before suggesting code changes:

1. Verify the change doesn't break existing functionality
2. Test with dry-run mode first
3. Validate against the vault index
4. Check error handling for edge cases
5. Ensure logging is appropriate

## Troubleshooting Guide for AI

### Common Issues

#### "API key not found"

- Check `ANTHROPIC_API_KEY` environment variable
- Check `.env` file in config directory
- Verify API key format (should start with `sk-ant-`)

#### "vault_path not set"

- Ensure `config.json` has absolute path to vault
- Use Windows-style paths with backslashes or forward slashes

#### "Folder does not exist"

- Claude suggested a folder that doesn't exist in vault
- Validation should catch this and fall back to "Inbox"
- Check vault index is up-to-date

#### "Append target not found"

- Claude suggested appending to a note that doesn't exist
- Validation should catch this and switch to "new" action
- Check vault index includes the target note
- **CRITICAL FIX (2026-02-25)**: Claude must ALWAYS return `folder` and `filename` fields, even when suggesting "append". If these fields are missing when the append target doesn't exist, the note will default to "Untitled.md" in Inbox. The system prompt now requires these fields for ALL actions as fallback handling.

#### "Invalid JSON response"

- Claude returned malformed JSON
- Check for markdown code fences in response
- Verify Claude is returning only JSON, no commentary

## Performance Considerations

- **Vault indexing**: Cached with SHA256 hash; rebuilds only when vault changes
- **API calls**: 30-second timeout; no retry logic
- **File settle time**: 5 seconds default to avoid processing incomplete writes
- **Log rotation**: 1 MB per file, keeps last 10 files
- **Task Scheduler**: 5-minute intervals to avoid excessive API calls

## Security Considerations

- **API key**: Stored in environment variable or `.env` file (not in config.json)
- **Vault access**: Requires read/write access to vault directory
- **File permissions**: Respects Windows file permissions
- **No PII logging**: Avoid logging sensitive information in debug mode

## Future Enhancement Ideas

1. **Retry logic**: Implement exponential backoff for API failures
2. **Batch processing**: Process multiple files in single API call
3. **Custom models**: Support for different Claude models per note type
4. **Wikilink suggestions**: Improve semantic relevance of suggested links
5. **Conflict resolution**: Handle simultaneous edits to same note
6. **Performance metrics**: Track filing decisions and success rates
7. **Integration with Obsidian API**: Direct vault manipulation instead of file-based
