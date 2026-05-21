# frozen_string_literal: true

require 'sketchup'

module Yoo
  module CustomToolbar
    # Load submodules
    require_relative 'settings_store'
    require_relative 'command_scanner'
    require_relative 'toolbar_manager'
    require_relative 'toolbar_builder_dialog'

    # Main entry point - called when extension loads
    def self.initialize_extension
      add_menu_items
      add_toolbar
      restore_toolbars
    end

    # Add menu items under Extensions
    def self.add_menu_items
      menu = UI.menu('Extensions')
      submenu = menu.add_submenu('Custom Toolbar Builder')

      submenu.add_item('Build Custom Toolbar...') do
        ToolbarBuilderDialog.show
      end

      submenu.add_separator

      submenu.add_item('Show All Toolbars') do
        show_all_toolbars
      end

      submenu.add_item('Hide All Toolbars') do
        hide_all_toolbars
      end

      submenu.add_separator

      submenu.add_item('Export Configuration...') do
        export_configuration
      end

      submenu.add_item('Import Configuration...') do
        import_configuration
      end
    end

    # Add the extension's own toolbar
    def self.add_toolbar
      toolbar = UI::Toolbar.new('Toolbar Builder')

      extension_dir = File.dirname(__FILE__)
      icons_dir = File.join(extension_dir, '..', 'icons')

      # Build Toolbar command
      build_cmd = UI::Command.new('Build Custom Toolbar') do
        ToolbarBuilderDialog.show
      end
      build_cmd.tooltip = 'Build Custom Toolbar'
      build_cmd.status_bar_text = 'Open the Custom Toolbar Builder dialog'
      build_cmd.menu_text = 'Build Custom Toolbar'

      # Try to find or use a default icon
      icon_path = File.join(icons_dir, 'toolbar_builder.svg')
      if File.exist?(icon_path)
        build_cmd.small_icon = icon_path
        build_cmd.large_icon = icon_path
      end

      toolbar.add_item(build_cmd)
      toolbar.show
    end

    # Restore saved toolbars on startup
    def self.restore_toolbars
      configs = SettingsStore.load_from_preferences
      return if configs.empty?

      # Slight delay to ensure other extensions have loaded their commands
      UI.start_timer(1.0, false) do
        ToolbarManager.rebuild_all_toolbars(configs)
      end
    end

    # Show all custom toolbars
    def self.show_all_toolbars
      configs = SettingsStore.load_from_preferences
      configs.each do |config|
        ToolbarManager.show_toolbar(config[:name])
      end
    end

    # Hide all custom toolbars
    def self.hide_all_toolbars
      configs = SettingsStore.load_from_preferences
      configs.each do |config|
        ToolbarManager.hide_toolbar(config[:name])
      end
    end

    # Export configuration via menu
    def self.export_configuration
      configs = SettingsStore.load_from_preferences
      if configs.empty?
        UI.messagebox('No toolbars to export. Create a toolbar first.')
        return
      end

      last_dir = SettingsStore.last_directory
      file_path = UI.savepanel('Export Toolbar Configuration', last_dir, 'CustomToolbars.json')

      return unless file_path

      SettingsStore.save_last_directory(File.dirname(file_path))
      if SettingsStore.export_config(configs, file_path)
        UI.messagebox("Configuration exported to:\n#{file_path}")
      else
        UI.messagebox('Failed to export configuration.')
      end
    end

    # Import configuration via menu
    def self.import_configuration
      last_dir = SettingsStore.last_directory
      file_path = UI.openpanel('Import Toolbar Configuration', last_dir, 'JSON Files|*.json||')

      return unless file_path

      unless File.exist?(file_path)
        UI.messagebox('File not found.')
        return
      end

      configs = SettingsStore.import_config(file_path)
      unless configs
        UI.messagebox('Invalid or corrupted configuration file.')
        return
      end

      # Confirm overwrite
      existing = SettingsStore.load_from_preferences
      unless existing.empty?
        result = UI.messagebox(
          "This will replace #{existing.length} existing toolbar(s) with #{configs.length} imported toolbar(s).\nContinue?",
          MB_YESNO
        )
        return unless result == IDYES
      end

      SettingsStore.save_last_directory(File.dirname(file_path))
      SettingsStore.save_to_preferences(configs)
      ToolbarManager.rebuild_all_toolbars(configs)

      UI.messagebox("Imported #{configs.length} toolbar(s).")
    end

    # Initialize when file is loaded
    unless file_loaded?(__FILE__)
      initialize_extension
      file_loaded(__FILE__)
    end
  end
end
