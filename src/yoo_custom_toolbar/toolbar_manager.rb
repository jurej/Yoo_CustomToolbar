# frozen_string_literal: true

require 'sketchup'

module Yoo
  module CustomToolbar
    # Manages creation and updates of custom toolbars
    module ToolbarManager
      @custom_toolbars = {}

      # Create or update a custom toolbar with the given configuration
      def self.create_or_update_toolbar(config)
        name = config[:name]
        return nil if name.nil? || name.empty?

        # Hide and release existing toolbar if present
        if @custom_toolbars.key?(name)
          existing = @custom_toolbars[name]
          existing.hide if existing.visible?
        end

        # Create new toolbar
        toolbar = UI::Toolbar.new(name)

        # Add commands to toolbar
        (config[:commands] || []).each do |cmd_config|
          command = find_or_create_command(cmd_config)
          toolbar.add_item(command) if command
        end

        # Store reference
        @custom_toolbars[name] = toolbar

        # Show toolbar
        toolbar.show

        toolbar
      end

      # Hide a custom toolbar
      def self.hide_toolbar(name)
        toolbar = @custom_toolbars[name]
        toolbar.hide if toolbar && toolbar.visible?
      end

      # Show a custom toolbar
      def self.show_toolbar(name)
        toolbar = @custom_toolbars[name]
        toolbar.show if toolbar && !toolbar.visible?
      end

      # Delete a custom toolbar
      def self.delete_toolbar(name)
        toolbar = @custom_toolbars.delete(name)
        if toolbar
          toolbar.hide if toolbar.visible?
          # Note: SketchUp API doesn't provide a way to truly destroy a toolbar
          # It will just be hidden
        end
      end

      # Get list of active custom toolbar names
      def self.active_toolbars
        @custom_toolbars.keys
      end

      # Find or create a command based on stored configuration
      def self.find_or_create_command(cmd_config)
        # Try to find existing command by reference
        existing_cmd = find_existing_command(cmd_config)
        return existing_cmd if existing_cmd

        # If not found, create a placeholder command that shows info
        create_placeholder_command(cmd_config)
      end

      # Attempt to find an existing command in ObjectSpace
      def self.find_existing_command(cmd_config)
        begin
          ObjectSpace.each_object(UI::Command) do |cmd|
            return cmd if command_matches?(cmd, cmd_config)
          end
        rescue => e
          puts "CustomToolbar: Error searching for existing command: #{e.message}"
        end
        nil
      end

      # Check if a command matches the stored configuration
      def self.command_matches?(command, cmd_config)
        # Match by menu text
        return true if command.menu_text && command.menu_text == cmd_config[:name]
        
        # Match by tooltip
        return true if command.tooltip && command.tooltip == cmd_config[:tooltip]
        
        # Match by icon path (base name)
        if cmd_config[:icon_path] && !cmd_config[:icon_path].empty?
          cmd_icon = File.basename(cmd_config[:icon_path])
          existing_icon = File.basename(command.small_icon || command.large_icon || '')
          return true if cmd_icon == existing_icon
        end
        
        false
      end

      # Create a placeholder command for missing commands
      def self.create_placeholder_command(cmd_config)
        cmd = UI::Command.new(cmd_config[:name] || 'Unknown') do
          UI.messagebox("Command '#{cmd_config[:name]}' could not be found.\nIt may belong to an extension that is not currently loaded.")
        end
        
        cmd.tooltip = cmd_config[:tooltip] || cmd_config[:name] || 'Unknown Command'
        cmd.status_bar_text = cmd_config[:status_bar_text] || "Command not available"
        cmd.menu_text = cmd_config[:name] || 'Unknown'
        
        # Try to set icon if path exists
        if cmd_config[:icon_path] && File.exist?(cmd_config[:icon_path])
          cmd.small_icon = cmd_config[:icon_path]
          cmd.large_icon = cmd_config[:icon_path]
        end
        
        cmd
      end

      # Rebuild all toolbars from saved configuration
      def self.rebuild_all_toolbars(configs)
        configs.each do |config|
          create_or_update_toolbar(config)
        end
      end
    end
  end
end
