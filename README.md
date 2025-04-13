# MailLogger

**Version: 2.5**  
**Author: Tc**

## Overview

MailLogger is a Classic World of Warcraft addon designed to track and log items received via mail, making it an essential tool for guild bank management. It automatically records all items and gold received through mail, and provides easy export functionality in both Discord-friendly and spreadsheet-compatible formats.

## Purpose

In Classic WoW, guild banks are typically managed through dedicated "bank alt" characters that receive and store donations from guild members. MailLogger helps guild bank managers by:

1. **Automatically tracking all donations** received via mail
2. **Recording sender information** to properly credit guild members
3. **Providing easy export options** to share donation information in Discord or import into spreadsheets
4. **Supporting multiple characters** for guilds with multiple bank alts

## Installation (if not curseforge)

1. Download the MailLogger addon
2. Extract the contents to your `World of Warcraft\_classic_\Interface\AddOns` directory
3. Ensure the folder structure is `Interface\AddOns\MailLogger\MailLogger.lua`
4. Restart World of Warcraft if it's currently running

## Features

### Automatic Mail Tracking
- Records sender name, items, quantities, and timestamp
- Tracks both items and gold received
- Works with regular and auto-looted mail

### Export Functionality
- Export in tab-separated value (TSV) format for spreadsheets
- Export in Discord-friendly inventory format
- View donations by individual item or summed by sender
- One-click copy for easy pasting

### Quality of Life
- Auto-display export pane when opening mailbox
- Movable export window
- Item name caching to handle disconnects and mail timing issues
- Multi-character support

## Commands

All commands start with `/maillog` followed by:

| Command | Description |
|---------|-------------|
| `show` | Display your mail item log in chat |
| `export` | Create copyable text of your log |
| `sum` | Export with common items summed |
| `toggle` | Show/hide the export pane |
| `auto` | Toggle automatic export pane display |
| `summode` | Toggle between regular and summed export |
| `clear` | Clear your mail log |
| `format` | Toggle between excel and discord format |
| `list` | List characters with mail logs |
| `fix` | Fix blank items in your log |
| `help` | Show help message |

## Usage Guide

### Basic Usage

1. **Log in to your guild bank character**
2. **Open your mailbox**
   - The export pane will automatically appear if auto-show is enabled
3. **Collect your mail as normal**
   - MailLogger will automatically track all items as you loot them
4. **Click "Highlight" to select the export text**
5. **Copy (Ctrl+C) and paste to Discord or a spreadsheet**

### Export Formats

#### Excel Format (Tab-separated)
This format is ideal for importing into spreadsheets:
```
MailLogger Export for YourCharacter-YourRealm
Date	Sender	Item	Quantity
2023-04-12 15:30:45	PlayerName	Flask of Petrification	2
2023-04-12 15:32:12	PlayerName	Elixir of Mongoose	5
```

#### Discord Format (Inventory Style)
This format is optimized for sharing in Discord:
```
MailLogger Inventory Export for YourCharacter-YourRealm

PlayerName:
  2 Flask of Petrification
  5 Elixir of Mongoose
  15 Oil of Immolation
  
AnotherPlayer:
  60 Sungrass
  15 Elixir of Greater Agility
```

### Switching Export Modes

- **Summed Mode**: Combines identical items from the same sender
- **Regular Mode**: Shows each mail transaction separately
- **Format Toggle**: Switch between spreadsheet (Excel) and Discord-friendly formats

## Guild Bank Management Tips

1. **Use Discord Format** for regular updates to your guild about donations
2. **Use Excel Format** for transferring data to guild bank spreadsheets
3. **Use Summed Mode** to get totals by player for weekly/monthly reports
4. **Clear logs periodically** after you've processed and recorded donations
5. **Install on all bank alts** if your guild uses multiple characters

## Troubleshooting

### Common Issues

- **Unknown Items**: If items show as "Unknown Item", use `/maillog fix` to attempt repair
- **Export Window Not Showing**: Use `/maillog toggle` to manually show the window
- **Disappearing After Mailbox Close**: This is by design - use `/maillog export` to show again

### Data Recovery

- Item logs are saved per character
- Use `/maillog list` to see all characters with saved logs
- Logs persist between game sessions

## Dependencies

MailLogger uses the following libraries:
- AceAddon-3.0
- AceConsole-3.0
- AceEvent-3.0
- AceHook-3.0
- AceDB-3.0

## Support

For issues or feature requests, please contact the author through curseforge :-)

## License

MailLogger is provided as-is for free use by the World of Warcraft community. Buy me a coffee though, [I love coffee!](buymeacoffee.com/tcole)