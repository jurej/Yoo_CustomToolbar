# frozen_string_literal: true

require 'sketchup'
require 'json'

module Yoo
  module CustomToolbar
    # Handles JSON serialization and SketchUp preferences storage
    module SettingsStore
      CONFIG_VERSION = 1

      def self.config_dir
        dir = File.join(Sketchup.find_support_file('Plugins'), 'yoo_custom_toolbar_data')
        Dir.mkdir(dir) unless Dir.exist?(dir)
        dir
      end

      def self.config_file
        File.join(config_dir, 'toolbar_configs.json')
      end

      def self.prefs_file
        File.join(config_dir, 'prefs.json')
      end

      # Export toolbar configuration to JSON file
      def self.export_config(toolbar_configs, file_path)
        data = {
          version: CONFIG_VERSION,
          exported_at: Time.now.iso8601,
          toolbars: toolbar_configs
        }
        File.write(file_path, JSON.pretty_generate(data))
        true
      rescue => e
        false
      end

      # Import toolbar configuration from JSON file
      def self.import_config(file_path)
        return nil unless File.exist?(file_path)

        data = JSON.parse(File.read(file_path), symbolize_names: true)
        return nil unless data[:version] && data[:toolbars]

        data[:toolbars]
      rescue => e
        nil
      end

      # Save toolbar configurations to a JSON file on disk
      def self.save_to_preferences(toolbar_configs)
        File.write(config_file, toolbar_configs.to_json)
      rescue => e
        # ignore
      end

      # Load toolbar configurations from JSON file on disk
      def self.load_from_preferences
        return [] unless File.exist?(config_file)

        json = File.read(config_file)
        return [] if json.nil? || json.strip.empty?

        JSON.parse(json, symbolize_names: true)
      rescue => e
        []
      end

      # Get the last used import/export directory
      def self.last_directory
        return Dir.home unless File.exist?(prefs_file)

        data = JSON.parse(File.read(prefs_file), symbolize_names: true)
        data[:last_directory] || Dir.home
      rescue => e
        Dir.home
      end

      # Save the last used import/export directory
      def self.save_last_directory(dir)
        existing = File.exist?(prefs_file) ? JSON.parse(File.read(prefs_file), symbolize_names: true) : {}
        File.write(prefs_file, existing.merge(last_directory: dir).to_json)
      rescue => e
        # ignore
      end
    end
  end
end
