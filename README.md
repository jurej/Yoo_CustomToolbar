# Custom Toolbar Builder for SketchUp

A SketchUp extension that allows you to build custom toolbars using buttons from existing extensions. Similar to Fredo LordofToolbars but simpler and more focused.

## Features

- **Select Commands**: Choose buttons from existing extensions that are currently loaded
- **Reorder**: Arrange buttons in your preferred order
- **Import/Export**: Save and share toolbar configurations as JSON files
- **Multiple Toolbars**: Create as many custom toolbars as you need
- **Persistent**: Toolbars are restored automatically when SketchUp starts

## Installation

1. Copy the `Yoo_CustomToolbar` folder to your SketchUp Plugins directory:
   - Windows: `%APPDATA%/SketchUp/SketchUp 2024/SketchUp/Plugins/`
   - Mac: `~/Library/Application Support/SketchUp 2024/SketchUp/Plugins/`

2. Restart SketchUp

3. The extension will appear under **Extensions > Custom Toolbar Builder**

## Usage

### Building a Custom Toolbar

1. Go to **Extensions > Custom Toolbar Builder > Build Custom Toolbar...**
2. Select commands from the left panel (Available Commands)
3. Click "Add Selected" to add them to your toolbar
4. Enter a name for your toolbar
5. Use the up/down arrows to reorder commands
6. Click "Save Toolbar"

Your custom toolbar will appear in SketchUp and be restored on startup.

### Managing Toolbars

- **Show/Hide**: Click the eye icon next to a saved toolbar
- **Edit**: Click on a saved toolbar name to edit its contents
- **Delete**: Click the trash icon to remove a toolbar

### Import/Export

- **Export**: Saves all your custom toolbar configurations to a JSON file
- **Import**: Loads toolbar configurations from a JSON file (replaces existing toolbars)

Access these via the **Extensions > Custom Toolbar Builder** menu or the Import/Export buttons in the dialog.

## How It Works

The extension discovers commands by:
1. Scanning all loaded `UI::Toolbar` instances
2. Collecting `UI::Command` objects from ObjectSpace
3. Building a registry of available commands with their icons and tooltips

When you create a toolbar, the extension:
1. Attempts to find existing matching commands (by name/tooltip/icon)
2. Falls back to creating placeholder commands if the original extension isn't loaded
3. Stores your configuration in SketchUp preferences and restores it on startup

## File Structure

```
Yoo_CustomToolbar/
├── src/
│   ├── Yoo_CustomToolbar.rb              # Extension loader
│   └── yoo_custom_toolbar/
│       ├── main.rb                        # Entry point
│       ├── command_scanner.rb             # Discovers available commands
│       ├── toolbar_manager.rb             # Creates/manages toolbars
│       ├── settings_store.rb              # JSON import/export & persistence
│       └── toolbar_builder_dialog.rb      # HtmlDialog UI
└── README.md
```

## Configuration Format

Exported JSON files have this structure:

```json
{
  "version": 1,
  "exported_at": "2026-01-15T10:30:00Z",
  "toolbars": [
    {
      "name": "My Custom Toolbar",
      "commands": [
        {
          "id": "abc123",
          "name": "BOQ Manager",
          "tooltip": "Open BOQ Manager",
          "icon_path": "...",
          "source_toolbar": "Yoo Estimator"
        }
      ]
    }
  ]
}
```

## Limitations

- Commands are discovered from loaded extensions only
- Some extensions may not expose their commands in a detectable way
- Icon paths are stored but may need manual adjustment if extensions move
- SketchUp API doesn't allow destroying toolbars, only hiding them

## License

Copyright 2026 Jure Judez
