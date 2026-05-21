# frozen_string_literal: true

require 'sketchup'
require 'digest'

module Yoo
  module CustomToolbar
    # Scans for available commands in loaded extensions
    module CommandScanner
      # Command registry to track commands as they're discovered
      @command_registry = {}

      # Scan for available commands using multiple strategies
      def self.scan_extensions_menu
        get_all_available_commands
      end

      # Register a command when it's created (hook for extensions to call)
      def self.register_command(command, source = 'Unknown')
        return unless command.is_a?(UI::Command)
        
        id = generate_command_id(command)
        @command_registry[id] = {
          id: id,
          name: command.menu_text || command.tooltip || 'Unknown',
          tooltip: command.tooltip || '',
          status_bar_text: command.status_bar_text || '',
          icon_path: command.small_icon || command.large_icon || '',
          source_toolbar: source,
          command_ref: command.object_id.to_s
        }
      end

      # Get all commands from the registry and ObjectSpace
      def self.get_all_available_commands
        begin
          # Deduplicate by Ruby object_id - each unique Command object appears once
          seen_object_ids = {}

          # Strategy 1: Scan ObjectSpace for all UI::Command instances (most complete source)
          object_space_count = 0
          begin
            ObjectSpace.each_object(UI::Command) do |cmd|
              oid = cmd.object_id
              next if seen_object_ids.key?(oid)
              object_space_count += 1
              seen_object_ids[oid] = {
                id: generate_command_id(cmd),
                name: cmd.menu_text || cmd.tooltip || 'Unknown',
                tooltip: cmd.tooltip || '',
                status_bar_text: cmd.status_bar_text || '',
                icon_path: cmd.small_icon || cmd.large_icon || '',
                source_toolbar: infer_source_toolbar(cmd),
                command_ref: oid.to_s
              }
            end
          rescue => e
            # ignore ObjectSpace scan errors
          end

          # Strategy 2: Registry may have better source names - update existing entries
          @command_registry.each do |_id, reg_cmd|
            oid = reg_cmd[:command_ref].to_i
            if seen_object_ids.key?(oid)
              seen_object_ids[oid][:source_toolbar] = reg_cmd[:source_toolbar] if reg_cmd[:source_toolbar] != 'Unknown'
            end
          end

          commands = seen_object_ids.values

          # Strategy 3: Discover commands from known extension modules (catches local vars)
          ext_commands = discover_from_extension_modules
          ext_commands.each do |ec|
            oid = ec[:command_ref].to_i
            next if seen_object_ids.key?(oid)
            commands << ec
          end
          commands.sort_by { |cmd| cmd[:name].downcase }
        rescue => e
          []
        end
      end

      # Try to infer which toolbar/plugin a command belongs to
      def self.infer_source_toolbar(command)
        begin
          # Check if command is registered with an explicit source
          id = generate_command_id(command)
          if @command_registry[id]
            return @command_registry[id][:source_toolbar]
          end

          # Derive plugin name from the icon file path
          # Most extensions store icons under .../Plugins/<plugin_folder>/...
          icon = command.small_icon || command.large_icon
          if icon && !icon.empty?
            parts = icon.gsub('\\', '/').split('/')
            plugins_idx = parts.rindex { |p| p.downcase == 'plugins' }
            if plugins_idx && parts.length > plugins_idx + 1
              folder = parts[plugins_idx + 1]
              # Clean up folder name: remove leading numbers/underscores, replace _ with space
              name = folder.gsub(/\A\d+_/, '').gsub('_', ' ').strip
              return name unless name.empty?
            end
            # Fallback: use the icon's immediate parent folder name
            parent = File.basename(File.dirname(icon))
            unless parent.empty? || parent == '.' || parent.downcase == 'plugins'
              return parent.gsub('_', ' ').strip
            end
          end

          # Try to match against live toolbar names
          UI::Toolbar.instances.each do |toolbar|
            if icon && toolbar.respond_to?(:name) && icon.include?(toolbar.name.gsub(' ', '_'))
              return toolbar.name
            end
          end
        rescue => e
          # Ignore errors in source inference
        end

        'Unknown'
      end

      # Discover commands from known extension modules
      def self.discover_from_extension_modules
        commands = []
        
        # Common extension modules and their patterns
        extension_patterns = [
          ['Yoo::Estimator', 'Yoo Estimator'],
          ['Fredo6', 'Fredo6 Tools'],
          ['TT_Lib', 'TT Library'],
          ['SketchUcation', 'SketchUcation'],
          ['TIG', 'TIG Plugins'],
          ['ThomThom', 'ThomThom Plugins']
        ]
        
        extension_patterns.each do |module_name, source_name|
          begin
            mod = Object.const_get(module_name) rescue next
            # Look for command constants or instance variables in the module
            scan_module_for_commands(mod, source_name, commands)
          rescue => e
            # Module not loaded, skip
          end
        end
        
        commands
      end

      # Scan a module for UI::Command instances
      def self.scan_module_for_commands(mod, source_name, commands)
        return unless mod.is_a?(Module)
        
        # Check constants
        mod.constants.each do |const_name|
          begin
            const = mod.const_get(const_name)
            if const.is_a?(UI::Command)
              commands << {
                id: generate_command_id(const),
                name: const.menu_text || const.tooltip || const_name.to_s,
                tooltip: const.tooltip || '',
                status_bar_text: const.status_bar_text || '',
                icon_path: const.small_icon || const.large_icon || '',
                source_toolbar: source_name,
                command_ref: const.object_id.to_s
              }
            end
          rescue
            # Skip constants that can't be accessed
          end
        end
        
        # Check instance variables if module has any
        if mod.respond_to?(:instance_variables)
          mod.instance_variables.each do |ivar|
            begin
              val = mod.instance_variable_get(ivar)
              if val.is_a?(UI::Command)
                commands << {
                  id: generate_command_id(val),
                  name: val.menu_text || val.tooltip || ivar.to_s,
                  tooltip: val.tooltip || '',
                  status_bar_text: val.status_bar_text || '',
                  icon_path: val.small_icon || val.large_icon || '',
                  source_toolbar: source_name,
                  command_ref: val.object_id.to_s
                }
              end
            rescue
              # Skip
            end
          end
        end
      end

      # Generate a unique ID for a command based on its properties
      def self.generate_command_id(command)
        begin
          text = command.menu_text || command.tooltip || command.object_id.to_s
          Digest::MD5.hexdigest(text + (command.status_bar_text || ''))[0..12]
        rescue => e
          Digest::MD5.hexdigest(command.object_id.to_s)[0..12]
        end
      end

    end
  end
end
