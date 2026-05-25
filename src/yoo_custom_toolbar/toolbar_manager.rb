# frozen_string_literal: true

require 'sketchup'
require 'digest'

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
          if cmd_config[:is_separator] || cmd_config[:id] == '__separator__'
            toolbar.add_separator
          else
            command = find_or_create_command(cmd_config)
            toolbar.add_item(command) if command
          end
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

      def self.default_icon_path
        File.join(File.dirname(__FILE__), '..', 'icons', 'default_command.svg')
      end

      # Find or create a command based on stored configuration
      def self.find_or_create_command(cmd_config)
        # Native SketchUp tools: create a send_action wrapper
        ref = cmd_config[:command_ref].to_s
        if ref.start_with?('native_') || cmd_config[:is_native]
          return create_native_command(cmd_config)
        end

        # Try to find existing command by reference
        existing_cmd = find_existing_command(cmd_config)
        if existing_cmd
          # Apply default icon if the real command has none
          if (existing_cmd.small_icon.nil? || existing_cmd.small_icon.empty?) &&
             (existing_cmd.large_icon.nil? || existing_cmd.large_icon.empty?)
            icon = default_icon_path
            if File.exist?(icon)
              existing_cmd.small_icon = icon
              existing_cmd.large_icon = icon
            end
          end
          return existing_cmd
        end

        # If not found, create a placeholder command that shows info
        create_placeholder_command(cmd_config)
      end

      # Create a UI::Command that invokes a native SketchUp tool via send_action
      def self.create_native_command(cmd_config)
        action = cmd_config[:native_action].to_s
        label  = cmd_config[:name] || 'Unknown'
        cmd = UI::Command.new(label) { Sketchup.send_action(action) }
        cmd.menu_text       = label
        cmd.tooltip         = cmd_config[:tooltip] || label
        cmd.status_bar_text = cmd_config[:status_bar_text] || label

        icon = cmd_config[:icon_path].to_s
        if icon.empty? || !File.exist?(icon)
          icon = default_icon_path
        end
        if File.exist?(icon)
          cmd.small_icon = icon
          cmd.large_icon = icon
        end

        cmd
      end

      # Compute the same stable ID that CommandScanner assigns to a live command.
      def self.stable_id_for(command)
        icon   = command.small_icon || command.large_icon || ''
        name   = command.menu_text  || command.tooltip    || ''
        status = command.status_bar_text || ''
        key = if !icon.empty?
          "#{File.basename(icon)}|#{name}|#{status}"
        elsif !name.empty?
          "#{name}|#{status}|#{command.object_id}"
        else
          command.object_id.to_s
        end
        Digest::MD5.hexdigest(key)
      rescue
        nil
      end

      # Attempt to find an existing command in ObjectSpace
      def self.find_existing_command(cmd_config)
        begin
          ref        = cmd_config[:command_ref].to_s
          saved_id   = cmd_config[:id].to_s

          # Step 1 — same-session: object_id exact match, corroborated by stable ID
          if ref =~ /\A\d+\z/
            ref_oid = ref.to_i
            ObjectSpace.each_object(UI::Command) do |cmd|
              next unless cmd.object_id == ref_oid
              return cmd if saved_id.empty? || stable_id_for(cmd) == saved_id
            end
          end

          # Step 2 — cross-session: match by recomputed stable ID (icon+name+status)
          unless saved_id.empty?
            ObjectSpace.each_object(UI::Command) do |cmd|
              return cmd if stable_id_for(cmd) == saved_id
            end
          end

          # Step 3 — last resort: fuzzy match by icon basename + corroborated name
          ObjectSpace.each_object(UI::Command) do |cmd|
            return cmd if command_matches?(cmd, cmd_config)
          end
        rescue => e
          # ignore
        end
        nil
      end

      # Check if a command matches the stored configuration
      def self.command_matches?(command, cmd_config)
        # Primary cross-session key: icon path base name (most unique per-command artifact)
        if cmd_config[:icon_path] && !cmd_config[:icon_path].empty?
          cmd_icon = File.basename(cmd_config[:icon_path])
          existing_icon = File.basename(command.small_icon || command.large_icon || '')
          return true if !cmd_icon.empty? && cmd_icon == existing_icon
        end

        # Secondary: name + source toolbar folder match (requires both to agree)
        if command.menu_text && command.menu_text == cmd_config[:name]
          src = cmd_config[:source_toolbar]
          # Only trust name match when we can corroborate via source toolbar path
          unless src.nil? || src.empty? || src == 'Unknown'
            icon = command.small_icon || command.large_icon || ''
            return true if icon.gsub('\\', '/').include?(src.gsub(' ', '_')) ||
                           icon.gsub('\\', '/').include?(src.gsub(' ', ''))
          end
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
        
        # Use saved icon path, fall back to default icon
        icon = if cmd_config[:icon_path] && !cmd_config[:icon_path].empty? && File.exist?(cmd_config[:icon_path])
          cmd_config[:icon_path]
        else
          default_icon_path
        end
        if File.exist?(icon)
          cmd.small_icon = icon
          cmd.large_icon = icon
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
