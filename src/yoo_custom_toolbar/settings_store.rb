# frozen_string_literal: true

require 'sketchup'
require 'json'

module Yoo
  module CustomToolbar
    # Handles JSON serialization and SketchUp preferences storage
    module SettingsStore
      PREFERENCES_KEY = 'YooCustomToolbar'.freeze
      CONFIG_VERSION = 1

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
        puts "Error exporting config: #{e.message}"
        false
      end

      # Import toolbar configuration from JSON file
      def self.import_config(file_path)
        return nil unless File.exist?(file_path)

        data = JSON.parse(File.read(file_path), symbolize_names: true)
        return nil unless data[:version] && data[:toolbars]

        data[:toolbars]
      rescue => e
        puts "Error importing config: #{e.message}"
        nil
      end

      # Save toolbar configurations to SketchUp preferences
      def self.save_to_preferences(toolbar_configs)
        Sketchup.write_default(PREFERENCES_KEY, 'toolbar_configs', toolbar_configs.to_json)
      rescue => e
        puts "Error saving to preferences: #{e.message}"
      end

      # Load toolbar configurations from SketchUp preferences
      def self.load_from_preferences
        json = Sketchup.read_default(PREFERENCES_KEY, 'toolbar_configs', nil)
        return [] unless json

        JSON.parse(json, symbolize_names: true)
      rescue => e
        puts "Error loading from preferences: #{e.message}"
        []
      end

      # Get the last used import/export directory
      def self.last_directory
        Sketchup.read_default(PREFERENCES_KEY, 'last_directory', Dir.home)
      end

      # Save the last used import/export directory
      def self.save_last_directory(dir)
        Sketchup.write_default(PREFERENCES_KEY, 'last_directory', dir)
      end
    end
  end
end
