# frozen_string_literal: true

require 'sketchup'

module Yoo
  module CustomToolbar
    # HtmlDialog for building custom toolbars
    module ToolbarBuilderDialog
      @dialog = nil

      # Show the toolbar builder dialog
      def self.show
        if @dialog && @dialog.visible?
          @dialog.bring_to_front
          return
        end

        @dialog = create_dialog
        setup_dialog_callbacks(@dialog)
        @dialog.show
      end

      # Push commands and saved toolbars to the dialog
      def self.push_data_to_dialog(dialog)
        begin
          commands = CommandScanner.get_all_available_commands
          configs = SettingsStore.load_from_preferences

          # Push commands in batches to avoid large-JSON issues
          # Normalize backslashes in icon paths so Windows paths don't break execute_script
          safe_commands = commands.map do |cmd|
            cmd.merge(icon_path: (cmd[:icon_path] || '').gsub('\\', '/'))
          end
          dialog.execute_script("window._cmdData = [];")
          
          safe_commands.each_slice(100) do |batch|
            json_batch = batch.to_json
            dialog.execute_script("window._cmdData = window._cmdData.concat(#{json_batch});")
          end
          
          dialog.execute_script("updateAvailableCommands(window._cmdData);")
          
          # Push saved toolbars (normalize icon paths for Windows)
          safe_configs = configs.map do |c|
            c.merge(commands: (c[:commands] || []).map { |cmd| cmd.merge(icon_path: (cmd[:icon_path] || '').gsub('\\', '/')) })
          end
          dialog.execute_script("updateSavedToolbars(#{safe_configs.to_json});")
        rescue => e
          # ignore
        end
      end

      # Close the dialog
      def self.close
        @dialog.close if @dialog
        @dialog = nil
      end

      private

      # Create the HtmlDialog
      def self.create_dialog
        dialog = UI::HtmlDialog.new(
          dialog_title: 'Custom Toolbar Builder',
          preferences_key: 'YooCustomToolbarBuilder',
          width: 900,
          height: 650,
          min_width: 700,
          min_height: 500,
          style: UI::HtmlDialog::STYLE_DIALOG
        )

        dialog.set_html(html_content)
        dialog
      end

      # Setup Ruby callbacks for the dialog
      def self.setup_dialog_callbacks(dialog)
        # Get available commands
        dialog.add_action_callback('get_available_commands') do |action_context|
          begin
            commands = CommandScanner.get_all_available_commands
            safe_commands = commands.map do |cmd|
              cmd.merge(icon_path: (cmd[:icon_path] || '').gsub('\\', '/'))
            end
            dialog.execute_script("window._cmdData = [];")
            safe_commands.each_slice(100) do |batch|
              dialog.execute_script("window._cmdData = window._cmdData.concat(#{batch.to_json});")
            end
            dialog.execute_script("updateAvailableCommands(window._cmdData);")
          rescue => e
            dialog.execute_script("loadCommandsError('#{e.message.gsub("'", "\\'")}')")
          end
        end

        # Get saved toolbar configurations
        dialog.add_action_callback('get_saved_toolbars') do |action_context|
          configs = SettingsStore.load_from_preferences
          safe_configs = configs.map do |c|
            c.merge(commands: (c[:commands] || []).map { |cmd| cmd.merge(icon_path: (cmd[:icon_path] || '').gsub('\\', '/')) })
          end
          dialog.execute_script("updateSavedToolbars(#{safe_configs.to_json})")
        end

        # Save toolbar configuration
        dialog.add_action_callback('save_toolbar') do |action_context, config_json|
          begin
            config = JSON.parse(config_json, symbolize_names: true)
            
            # Load existing configs, update or add new
            configs = SettingsStore.load_from_preferences
            existing_index = configs.find_index { |c| c[:name] == config[:name] }
            
            if existing_index
              configs[existing_index] = config
            else
              configs << config
            end
            
            SettingsStore.save_to_preferences(configs)
            ToolbarManager.create_or_update_toolbar(config)
            
            dialog.execute_script("saveSuccess('#{config[:name]}')")
          rescue => e
            dialog.execute_script("saveError('#{e.message.gsub("'", "\\'")}')")
          end
        end

        # Delete toolbar
        dialog.add_action_callback('delete_toolbar') do |action_context, name|
          begin
            configs = SettingsStore.load_from_preferences
            configs.reject! { |c| c[:name] == name }
            SettingsStore.save_to_preferences(configs)
            ToolbarManager.delete_toolbar(name)
            dialog.execute_script("deleteSuccess('#{name}')")
          rescue => e
            dialog.execute_script("deleteError('#{e.message.gsub("'", "\\'")}')')")
          end
        end

        # Export configuration
        dialog.add_action_callback('export_config') do |action_context|
          begin
            configs = SettingsStore.load_from_preferences
            if configs.empty?
              dialog.execute_script("exportError('No toolbars to export')")
              next
            end

            last_dir = SettingsStore.last_directory
            file_path = UI.savepanel('Export Toolbar Configuration', last_dir, 'CustomToolbars.json')
            
            if file_path
              SettingsStore.save_last_directory(File.dirname(file_path))
              if SettingsStore.export_config(configs, file_path)
                dialog.execute_script("exportSuccess('#{file_path.gsub("'", "\\'")}')")
              else
                dialog.execute_script("exportError('Failed to write file')")
              end
            end
          rescue => e
            dialog.execute_script("exportError('#{e.message.gsub("'", "\\'")}')")
          end
        end

        # Import configuration
        dialog.add_action_callback('import_config') do |action_context|
          begin
            last_dir = SettingsStore.last_directory
            file_path = UI.openpanel('Import Toolbar Configuration', last_dir, 'JSON Files|*.json||')
            
            if file_path
              SettingsStore.save_last_directory(File.dirname(file_path))
              configs = SettingsStore.import_config(file_path)
              
              if configs
                SettingsStore.save_to_preferences(configs)
                ToolbarManager.rebuild_all_toolbars(configs)
                dialog.execute_script("importSuccess(#{configs.to_json})")
              else
                dialog.execute_script("importError('Invalid or corrupted file')")
              end
            end
          rescue => e
            dialog.execute_script("importError('#{e.message.gsub("'", "\\'")}')")
          end
        end

        # Show toolbar
        dialog.add_action_callback('show_toolbar') do |action_context, name|
          ToolbarManager.show_toolbar(name)
        end

        # Hide toolbar
        dialog.add_action_callback('hide_toolbar') do |action_context, name|
          ToolbarManager.hide_toolbar(name)
        end

        # Dialog closed
        dialog.add_action_callback('dialog_closed') do |action_context|
          @dialog = nil
        end
      end

      # HTML content for the dialog
      def self.html_content
        default_icon = File.join(File.dirname(__FILE__), '..', 'icons', 'default_command.svg').gsub('\\', '/')
        <<-HTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <style>
    /* ── Modus design tokens (subset from modus-wc-styles) ── */
    :root {
      --m-white:        #ffffff;
      --m-gray-light:   #f1f1f6;
      --m-gray-01:      #f5f5f8;
      --m-gray-02:      #e9eaf0;
      --m-gray-0:       #e0e1e9;
      --m-gray-1:       #cbcdd6;
      --m-gray-2:       #b7b9c3;
      --m-gray-5:       #7d808d;
      --m-gray-6:       #6a6e79;
      --m-gray-7:       #585c65;
      --m-gray-8:       #464b52;
      --m-gray-9:       #353a40;
      --m-gray-10:      #171c1e;
      --m-trimble-gray: #252a2e;
      --m-blue-pale:    #dcedf9;
      --m-blue-light:   #217cbb;
      --m-trimble-blue: #0063a3;
      --m-blue-dark:    #0e416c;
      --m-red:          #da212c;
      --m-red-light:    #e86363;
      --m-red-pale:     #fbd4d7;
      --m-green:        #1e8a44;
      --m-green-pale:   #e0eccf;
      --m-yellow:       #fbad26;

      --m-font:         'Segoe UI', 'San Francisco', 'Helvetica Neue', Arial, sans-serif;
      --m-fs-xs:        0.625rem;
      --m-fs-sm:        0.75rem;
      --m-fs-md:        0.875rem;
      --m-fs-lg:        1rem;

      --m-fw-normal:    400;
      --m-fw-semi:      600;
      --m-fw-bold:      700;

      --m-sp-2xs:       0.125rem;
      --m-sp-xs:        0.25rem;
      --m-sp-sm:        0.5rem;
      --m-sp-md:        0.75rem;
      --m-sp-lg:        1rem;
      --m-sp-xl:        1.5rem;

      --m-radius-sm:    2px;
      --m-radius-md:    4px;
      --m-radius-lg:    8px;
      --m-radius-btn:   var(--m-radius-lg);
      --m-radius-input: var(--m-radius-lg);
      --m-radius-card:  var(--m-radius-lg);
    }

    /* ── Reset ── */
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

    body {
      font-family: var(--m-font);
      font-size: var(--m-fs-md);
      font-weight: var(--m-fw-normal);
      color: var(--m-gray-10);
      background: var(--m-gray-01);
      height: 100vh;
      display: flex;
      flex-direction: column;
      overflow: hidden;
    }

    /* ── App header (Trimble blue nav bar) ── */
    .app-header {
      background: var(--m-trimble-blue);
      color: var(--m-white);
      height: 48px;
      padding: 0 var(--m-sp-xl);
      display: flex;
      align-items: center;
      justify-content: space-between;
      flex-shrink: 0;
      box-shadow: 0 1px 4px rgba(0,0,0,0.25);
    }
    .app-header-brand {
      display: flex;
      align-items: center;
      gap: var(--m-sp-sm);
    }
    .app-header-brand svg {
      width: 20px; height: 20px; fill: var(--m-white); flex-shrink: 0;
    }
    .app-header-title {
      font-size: var(--m-fs-lg);
      font-weight: var(--m-fw-semi);
      letter-spacing: 0.01em;
    }
    .app-header-actions {
      display: flex;
      gap: var(--m-sp-sm);
    }

    /* ── Modus buttons ── */
    .btn {
      display: inline-flex;
      align-items: center;
      gap: var(--m-sp-xs);
      padding: 0 var(--m-sp-lg);
      height: 32px;
      border: 1px solid transparent;
      border-radius: var(--m-radius-btn);
      font-family: var(--m-font);
      font-size: var(--m-fs-md);
      font-weight: var(--m-fw-semi);
      cursor: pointer;
      white-space: nowrap;
      transition: background 0.15s, border-color 0.15s, color 0.15s;
      text-decoration: none;
    }
    .btn-primary {
      background: var(--m-trimble-blue);
      color: var(--m-white);
      border-color: var(--m-trimble-blue);
    }
    .btn-primary:hover { background: var(--m-blue-dark); border-color: var(--m-blue-dark); }

    .btn-outline {
      background: transparent;
      color: var(--m-white);
      border-color: rgba(255,255,255,0.6);
    }
    .btn-outline:hover { background: rgba(255,255,255,0.12); border-color: var(--m-white); }

    .btn-tertiary {
      background: var(--m-gray-01);
      color: var(--m-gray-8);
      border-color: var(--m-gray-1);
    }
    .btn-tertiary:hover { background: var(--m-gray-02); border-color: var(--m-gray-2); }

    .btn-danger {
      background: transparent;
      color: var(--m-red);
      border-color: var(--m-red);
    }
    .btn-danger:hover { background: var(--m-red-pale); }

    /* ── Layout ── */
    .main-content {
      flex: 1;
      display: flex;
      padding: var(--m-sp-lg);
      gap: var(--m-sp-lg);
      overflow: hidden;
      min-height: 0;
    }

    /* ── Panel card ── */
    .panel {
      background: var(--m-white);
      border: 1px solid var(--m-gray-02);
      border-radius: var(--m-radius-card);
      box-shadow: 0 1px 3px rgba(0,0,0,0.06);
      display: flex;
      flex-direction: column;
      overflow: hidden;
      min-height: 0;
    }
    .panel-left  { flex: 1; min-width: 280px; }
    .panel-right { flex: 1; min-width: 280px; }

    .panel-header {
      background: var(--m-gray-01);
      border-bottom: 1px solid var(--m-gray-02);
      padding: var(--m-sp-sm) var(--m-sp-lg);
      display: flex;
      align-items: center;
      flex-shrink: 0;
    }
    .panel-header h2 {
      font-size: var(--m-fs-sm);
      font-weight: var(--m-fw-semi);
      color: var(--m-gray-7);
      text-transform: uppercase;
      letter-spacing: 0.06em;
    }

    /* ── Search ── */
    .search-box {
      padding: var(--m-sp-sm) var(--m-sp-lg);
      border-bottom: 1px solid var(--m-gray-02);
      flex-shrink: 0;
    }
    .search-box input {
      width: 100%;
      height: 32px;
      padding: 0 var(--m-sp-md);
      border: 1px solid var(--m-gray-1);
      border-radius: var(--m-radius-input);
      font-family: var(--m-font);
      font-size: var(--m-fs-md);
      color: var(--m-gray-10);
      background: var(--m-white);
      outline: none;
      transition: border-color 0.15s, box-shadow 0.15s;
    }
    .search-box input::placeholder { color: var(--m-gray-5); }
    .search-box input:focus {
      border-color: var(--m-trimble-blue);
      box-shadow: 0 0 0 2px rgba(0,99,163,0.18);
    }

    /* ── Scrollable list ── */
    .list-container {
      flex: 1;
      overflow-y: auto;
      padding: var(--m-sp-sm);
      min-height: 0;
    }
    .list-container::-webkit-scrollbar { width: 6px; }
    .list-container::-webkit-scrollbar-thumb {
      background: var(--m-gray-1);
      border-radius: 3px;
    }

    /* ── Command group header ── */
    .cmd-group-header {
      display: flex;
      align-items: center;
      gap: var(--m-sp-xs);
      padding: var(--m-sp-xs) var(--m-sp-sm);
      margin-top: var(--m-sp-xs);
      background: var(--m-gray-02);
      border-radius: var(--m-radius-md);
      cursor: pointer;
      user-select: none;
      font-size: var(--m-fs-xs);
      font-weight: var(--m-fw-bold);
      color: var(--m-gray-7);
      text-transform: uppercase;
      letter-spacing: 0.06em;
      border: none;
      width: 100%;
      text-align: left;
    }
    .cmd-group-header:hover { background: var(--m-gray-0); }
    .cmd-group-header .group-chevron {
      font-size: 10px;
      transition: transform 0.15s;
      flex-shrink: 0;
    }
    .cmd-group-header.collapsed .group-chevron { transform: rotate(-90deg); }
    .cmd-group-header .group-count {
      margin-left: auto;
      font-weight: var(--m-fw-normal);
      color: var(--m-gray-5);
      font-size: var(--m-fs-xs);
    }
    .cmd-group-body.collapsed { display: none; }

    /* ── Available command item ── */
    .command-item {
      display: flex;
      align-items: center;
      padding: var(--m-sp-sm) var(--m-sp-md);
      border: 1px solid var(--m-gray-02);
      border-radius: var(--m-radius-md);
      margin-bottom: var(--m-sp-xs);
      cursor: pointer;
      background: var(--m-white);
      transition: background 0.12s, border-color 0.12s;
    }
    .command-item:hover {
      background: var(--m-gray-01);
      border-color: var(--m-blue-light);
    }
    .command-item input[type="checkbox"] {
      width: 16px; height: 16px;
      margin-right: var(--m-sp-sm);
      cursor: pointer;
      flex-shrink: 0;
      accent-color: var(--m-trimble-blue);
    }
    .cmd-icon {
      width: 20px; height: 20px;
      margin-right: var(--m-sp-sm);
      flex-shrink: 0;
      object-fit: contain;
      border-radius: 2px;
    }
    .command-info { flex: 1; min-width: 0; }
    .command-name {
      font-size: var(--m-fs-md);
      font-weight: var(--m-fw-semi);
      color: var(--m-gray-10);
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .command-source {
      font-size: var(--m-fs-xs);
      color: var(--m-gray-6);
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }

    /* ── Panel footer ── */
    .panel-footer {
      padding: var(--m-sp-sm) var(--m-sp-lg);
      border-top: 1px solid var(--m-gray-02);
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: var(--m-sp-sm);
      flex-shrink: 0;
      background: var(--m-gray-01);
    }
    .panel-footer-left {
      font-size: var(--m-fs-sm);
      color: var(--m-gray-6);
    }
    .panel-footer-right {
      display: flex;
      gap: var(--m-sp-sm);
    }

    /* ── Toolbar name input ── */
    .toolbar-config {
      padding: var(--m-sp-sm) var(--m-sp-lg);
      border-bottom: 1px solid var(--m-gray-02);
      flex-shrink: 0;
    }
    .toolbar-config label {
      display: block;
      font-size: var(--m-fs-xs);
      font-weight: var(--m-fw-semi);
      color: var(--m-gray-6);
      text-transform: uppercase;
      letter-spacing: 0.06em;
      margin-bottom: var(--m-sp-xs);
    }
    .toolbar-config input {
      width: 100%;
      height: 32px;
      padding: 0 var(--m-sp-md);
      border: 1px solid var(--m-gray-1);
      border-radius: var(--m-radius-input);
      font-family: var(--m-font);
      font-size: var(--m-fs-md);
      color: var(--m-gray-10);
      background: var(--m-white);
      outline: none;
      transition: border-color 0.15s, box-shadow 0.15s;
    }
    .toolbar-config input:focus {
      border-color: var(--m-trimble-blue);
      box-shadow: 0 0 0 2px rgba(0,99,163,0.18);
    }

    /* ── Selected list ── */
    .selected-list {
      flex: 1;
      overflow-y: auto;
      padding: var(--m-sp-sm);
      min-height: 0;
    }
    .selected-list::-webkit-scrollbar { width: 6px; }
    .selected-list::-webkit-scrollbar-thumb {
      background: var(--m-gray-1);
      border-radius: 3px;
    }

    .selected-item {
      display: flex;
      align-items: center;
      padding: var(--m-sp-xs) var(--m-sp-sm);
      background: var(--m-gray-01);
      border: 1px solid var(--m-gray-02);
      border-radius: var(--m-radius-md);
      margin-bottom: var(--m-sp-xs);
      gap: var(--m-sp-xs);
      min-height: 40px;
    }
    .selected-item .drag-handle {
      color: var(--m-gray-2);
      cursor: grab;
      font-size: 14px;
      flex-shrink: 0;
      padding: 0 var(--m-sp-2xs);
      user-select: none;
    }
    .selected-item .drag-handle:active { cursor: grabbing; }
    .selected-item .item-icon {
      width: 18px; height: 18px;
      flex-shrink: 0;
      object-fit: contain;
      border-radius: 2px;
    }
    .selected-item .item-info {
      flex: 1;
      min-width: 0;
      overflow: hidden;
    }
    .selected-item .item-name {
      font-size: var(--m-fs-md);
      font-weight: var(--m-fw-semi);
      color: var(--m-gray-9);
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .selected-item .item-subname {
      font-size: var(--m-fs-xs);
      color: var(--m-gray-5);
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .selected-item .remove-btn {
      background: none;
      border: none;
      color: var(--m-gray-5);
      cursor: pointer;
      font-size: 16px;
      padding: 0 var(--m-sp-2xs);
      flex-shrink: 0;
      line-height: 1;
      border-radius: var(--m-radius-sm);
      transition: color 0.12s, background 0.12s;
    }
    .selected-item .remove-btn:hover {
      color: var(--m-red);
      background: var(--m-red-pale);
    }

    /* ── Drop indicator ── */
    .drop-indicator {
      height: 2px;
      background: var(--m-trimble-blue);
      border-radius: 1px;
      margin: -1px 0;
      pointer-events: none;
      display: none;
      box-shadow: 0 0 4px rgba(0,99,163,0.4);
    }
    .drop-indicator.active { display: block; }

    /* ── Separator item ── */
    .selected-item.separator {
      background: transparent;
      border: none;
      border-top: 2px dashed var(--m-gray-1);
      border-radius: 0;
      padding: var(--m-sp-xs) var(--m-sp-sm);
      min-height: 24px;
      justify-content: space-between;
    }
    .selected-item.separator .sep-label {
      flex: 1;
      text-align: center;
      font-size: var(--m-fs-xs);
      font-weight: var(--m-fw-semi);
      color: var(--m-gray-2);
      letter-spacing: 0.1em;
      text-transform: uppercase;
      pointer-events: none;
    }

    /* ── Saved toolbars panel ── */
    .saved-toolbars {
      width: 230px;
      background: var(--m-white);
      border: 1px solid var(--m-gray-02);
      border-radius: var(--m-radius-card);
      box-shadow: 0 1px 3px rgba(0,0,0,0.06);
      display: flex;
      flex-direction: column;
      overflow: hidden;
      flex-shrink: 0;
    }

    .toolbar-list-item {
      padding: var(--m-sp-sm) var(--m-sp-lg);
      border-bottom: 1px solid var(--m-gray-01);
      cursor: pointer;
      display: flex;
      justify-content: space-between;
      align-items: center;
      transition: background 0.12s;
    }
    .toolbar-list-item:hover { background: var(--m-gray-01); }
    .toolbar-list-item.active {
      background: var(--m-blue-pale);
      border-left: 3px solid var(--m-trimble-blue);
      padding-left: calc(var(--m-sp-lg) - 3px);
    }
    .toolbar-list-item .toolbar-name {
      font-size: var(--m-fs-md);
      font-weight: var(--m-fw-semi);
      color: var(--m-gray-9);
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .toolbar-list-item .toolbar-actions {
      display: flex;
      gap: var(--m-sp-2xs);
      flex-shrink: 0;
    }
    .toolbar-list-item .toolbar-actions button {
      background: none;
      border: none;
      cursor: pointer;
      font-size: 14px;
      padding: 2px 4px;
      color: var(--m-gray-5);
      border-radius: var(--m-radius-sm);
      transition: color 0.12s, background 0.12s;
    }
    .toolbar-list-item .toolbar-actions button:hover {
      color: var(--m-gray-9);
      background: var(--m-gray-02);
    }

    /* ── Empty state ── */
    .empty-state {
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: var(--m-sp-xl) var(--m-sp-lg);
      color: var(--m-gray-5);
      text-align: center;
      gap: var(--m-sp-sm);
    }
    .empty-state-icon { font-size: 36px; opacity: 0.4; }
    .empty-state p { font-size: var(--m-fs-sm); line-height: 1.5; }

    /* ── Toast notification ── */
    .status-message {
      position: fixed;
      bottom: 20px;
      right: 20px;
      padding: var(--m-sp-sm) var(--m-sp-lg);
      border-radius: var(--m-radius-md);
      font-size: var(--m-fs-md);
      font-weight: var(--m-fw-semi);
      animation: slideIn 0.2s ease;
      z-index: 1000;
      box-shadow: 0 4px 12px rgba(0,0,0,0.15);
      max-width: 320px;
    }
    .status-message.success {
      background: var(--m-green-pale);
      color: var(--m-green);
      border-left: 4px solid var(--m-green);
    }
    .status-message.error {
      background: var(--m-red-pale);
      color: var(--m-red);
      border-left: 4px solid var(--m-red);
    }
    @keyframes slideIn {
      from { transform: translateY(8px); opacity: 0; }
      to   { transform: translateY(0);   opacity: 1; }
    }
  </style>
</head>
<body>
  <!-- Trimble blue app header -->
  <header class="app-header">
    <div class="app-header-brand">
      <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
        <path d="M3 4h18v2H3V4zm0 7h18v2H3v-2zm0 7h18v2H3v-2z"/>
      </svg>
      <span class="app-header-title">Custom Toolbar Builder</span>
    </div>
    <div class="app-header-actions">
      <button class="btn btn-outline" onclick="importConfig()">&#8593; Import</button>
      <button class="btn btn-outline" onclick="exportConfig()">&#8595; Export</button>
    </div>
  </header>

  <div class="main-content">
    <!-- Left: available commands -->
    <div class="panel panel-left">
      <div class="panel-header">
        <h2>Available Commands</h2>
      </div>
      <div class="search-box">
        <input type="text" id="searchInput" placeholder="Search by plugin or command name…" onkeyup="filterCommands()">
      </div>
      <div class="list-container" id="availableList">
        <div class="empty-state">
          <div class="empty-state-icon">&#8635;</div>
          <p>Loading commands…</p>
        </div>
      </div>
      <div class="panel-footer">
        <span class="panel-footer-left" id="availableCount">0 commands</span>
        <div class="panel-footer-right">
          <button class="btn btn-primary" onclick="addSelectedCommands()">Add Selected</button>
        </div>
      </div>
    </div>

    <!-- Right: selected commands -->
    <div class="panel panel-right">
      <div class="panel-header">
        <h2>Toolbar Contents</h2>
      </div>
      <div class="toolbar-config">
        <label>Toolbar Name</label>
        <input type="text" id="toolbarName" placeholder="Enter toolbar name…">
      </div>
      <div class="selected-list" id="selectedList">
        <div class="empty-state">
          <div class="empty-state-icon">&#9776;</div>
          <p>Select commands from the left<br>to build your toolbar</p>
        </div>
      </div>
      <div class="panel-footer">
        <div class="panel-footer-left">
          <button class="btn btn-danger" onclick="clearSelection()">Clear</button>
        </div>
        <div class="panel-footer-right">
          <button class="btn btn-tertiary" onclick="addSeparator()">+ Separator</button>
          <button class="btn btn-primary" onclick="saveToolbar()">Save Toolbar</button>
        </div>
      </div>
    </div>

    <!-- Saved toolbars sidebar -->
    <div class="saved-toolbars">
      <div class="panel-header">
        <h2>Saved Toolbars</h2>
      </div>
      <div class="list-container" id="savedList">
        <div class="empty-state">
          <p>No saved toolbars</p>
        </div>
      </div>
    </div>
  </div>

  <script>
    let availableCommands = [];
    let selectedCommands = [];
    let savedToolbars = [];
    let currentToolbarName = '';
    var DEFAULT_ICON = '#{default_icon}';
    var dragSrcIndex = null;
    var dropTargetIndex = null;
    var collapsedGroups = {};

    // Pull data from Ruby once DOM is ready - avoids execute_script race condition
    document.addEventListener('DOMContentLoaded', function() {
      if (typeof sketchup !== 'undefined') {
        sketchup.get_available_commands();
        sketchup.get_saved_toolbars();
      }
    });

    // Fallback: if no data arrives within 8 seconds, show error
    setTimeout(function() {
      if (availableCommands.length === 0) {
        document.getElementById('availableList').innerHTML =
          '<div class="empty-state"><p>No commands loaded.<br>Check Ruby Console for errors.</p></div>';
      }
    }, 8000);

    // Update available commands from Ruby
    function updateAvailableCommands(commands) {
      try {
        availableCommands = commands;
        renderAvailableList();
        var countEl = document.getElementById('availableCount');
        if (countEl) countEl.textContent = commands.length + ' commands';
      } catch(e) {
        document.getElementById('availableList').innerHTML =
          '<div class="empty-state"><p>JS Error: ' + e.message + '</p></div>';
      }
    }

    // Update saved toolbars from Ruby
    function updateSavedToolbars(toolbars) {
      savedToolbars = toolbars || [];
      renderSavedList();
    }

    // Render available commands list
    function renderAvailableList() {
      try {
        var list = document.getElementById('availableList');
        var searchInput = document.getElementById('searchInput');
        var searchTerm = searchInput ? searchInput.value.toLowerCase() : '';

        var filtered = availableCommands.filter(function(cmd) {
          return cmd.name.toLowerCase().includes(searchTerm) ||
            (cmd.tooltip && cmd.tooltip.toLowerCase().includes(searchTerm)) ||
            (cmd.source_toolbar && cmd.source_toolbar !== 'Unknown' && cmd.source_toolbar.toLowerCase().includes(searchTerm));
        });

        if (filtered.length === 0) {
          list.innerHTML = '<div class="empty-state"><p>No commands found</p></div>';
          var countEl = document.getElementById('availableCount');
          if (countEl) countEl.textContent = '0 commands';
          return;
        }

        // Group by source_toolbar
        var groups = {};
        var groupOrder = [];
        filtered.forEach(function(cmd) {
          var src = (cmd.source_toolbar && cmd.source_toolbar !== 'Unknown') ? cmd.source_toolbar : 'Other';
          if (!groups[src]) { groups[src] = []; groupOrder.push(src); }
          groups[src].push(cmd);
        });
        groupOrder.sort(function(a, b) {
          if (a === 'SketchUp') return -1;
          if (b === 'SketchUp') return 1;
          if (a === 'Other') return 1;
          if (b === 'Other') return -1;
          return a.localeCompare(b);
        });

        var isSearching = searchTerm.length > 0;
        var html = '';
        groupOrder.forEach(function(src) {
          var cmds = groups[src];
          var groupId = 'grp_' + src.replace(/[^a-z0-9]/gi, '_');
          var collapsed = (!isSearching && collapsedGroups[src]) ? 'collapsed' : '';
          html += '<button class="cmd-group-header ' + collapsed + '" data-group="' + escapeHtml(src) + '" data-body="' + groupId + '">' +
            '<span class="group-chevron">&#9660;</span>' +
            escapeHtml(src) +
            '<span class="group-count">' + cmds.length + '</span>' +
          '</button>';
          html += '<div class="cmd-group-body ' + collapsed + '" id="' + groupId + '">';
          cmds.forEach(function(cmd) {
            var iconHtml = '<img class="cmd-icon" src="' + (cmd.icon_path || DEFAULT_ICON) + '">';
            html += '<div class="command-item" data-id="' + cmd.command_ref + '">' +
              '<input type="checkbox" value="' + cmd.command_ref + '" onchange="toggleSelection(this)">' +
              iconHtml +
              '<div class="command-info">' +
                '<div class="command-name">' + escapeHtml(cmd.name) + '</div>' +
              '</div>' +
            '</div>';
          });
          html += '</div>';
        });

        list.innerHTML = html;

        // Collapse toggle via event delegation
        list.querySelectorAll('.cmd-group-header').forEach(function(header) {
          header.addEventListener('click', function() {
            var src = header.getAttribute('data-group');
            var bodyId = header.getAttribute('data-body');
            var body = document.getElementById(bodyId);
            var isNowCollapsed = header.classList.toggle('collapsed');
            body.classList.toggle('collapsed', isNowCollapsed);
            collapsedGroups[src] = isNowCollapsed;
          });
        });

        var countEl = document.getElementById('availableCount');
        if (countEl) countEl.textContent = filtered.length + ' commands';
      } catch(e) {
        document.getElementById('availableList').innerHTML =
          '<div class="empty-state"><p>Render Error: ' + e.message + '</p></div>';
      }
    }

    // Render selected commands list
    function renderSelectedList() {
      var list = document.getElementById('selectedList');
      
      if (selectedCommands.length === 0) {
        list.innerHTML = '<div class="empty-state"><div class="empty-state-icon">☰</div><p>Select commands from the left<br>to build your toolbar</p></div>';
        return;
      }

      list.innerHTML = selectedCommands.map(function(cmd, index) {
        if (cmd.is_separator) {
          return '<div class="selected-item separator" draggable="true" data-index="' + index + '">' +
            '<span class="sep-label">separator</span>' +
            '<button class="remove-btn" data-index="' + index + '">×</button>' +
          '</div>';
        }
        var iconHtml = '<img class="item-icon" src="' + (cmd.icon_path || DEFAULT_ICON) + '">';
        var sourceLine = (cmd.source_toolbar && cmd.source_toolbar !== 'Unknown') ? cmd.source_toolbar : '';
        return '<div class="selected-item" draggable="true" data-index="' + index + '">' +
          '<span class="drag-handle">☰</span>' +
          iconHtml +
          '<div class="item-info">' +
            (sourceLine ? '<div class="item-name">' + escapeHtml(sourceLine) + '</div>' : '') +
            '<div class="item-subname">' + escapeHtml(cmd.name) + '</div>' +
          '</div>' +
          '<button class="remove-btn" data-index="' + index + '">×</button>' +
        '</div>';
      }).join('');

      // Click handler for remove
      list.onclick = function(e) {
        var target = e.target;
        if (target.classList.contains('remove-btn')) {
          var idx = parseInt(target.getAttribute('data-index'));
          if (!isNaN(idx)) removeItem(idx);
        }
      };

      // Drag-and-drop reordering — dragSrcIndex/dropTargetIndex are module-level
      // so closures always share the same binding across re-renders
      var allItems = Array.prototype.slice.call(list.querySelectorAll('.selected-item'));

      // Insert indicator divs between items
      var indicators = [];
      allItems.forEach(function(item) {
        var ind = document.createElement('div');
        ind.className = 'drop-indicator';
        list.insertBefore(ind, item);
        indicators.push(ind);
      });
      var endInd = document.createElement('div');
      endInd.className = 'drop-indicator';
      list.appendChild(endInd);
      indicators.push(endInd);

      function clearIndicators() {
        indicators.forEach(function(ind) { ind.classList.remove('active'); });
        dropTargetIndex = null;
      }

      function getInsertIndex(clientY) {
        for (var i = 0; i < allItems.length; i++) {
          var rect = allItems[i].getBoundingClientRect();
          if (clientY < rect.top + rect.height / 2) return i;
        }
        return allItems.length;
      }

      // dragstart / dragend via event delegation on the list
      list.addEventListener('dragstart', function(e) {
        var item = e.target.closest('.selected-item');
        if (!item) return;
        dragSrcIndex = parseInt(item.getAttribute('data-index'));
        e.dataTransfer.effectAllowed = 'move';
        setTimeout(function() { item.style.opacity = '0.4'; }, 0);
      });

      list.addEventListener('dragend', function(e) {
        var item = e.target.closest('.selected-item');
        if (item) item.style.opacity = '';
        clearIndicators();
      });

      list.addEventListener('dragover', function(e) {
        e.preventDefault();
        e.dataTransfer.dropEffect = 'move';
        var idx = getInsertIndex(e.clientY);
        if (idx !== dropTargetIndex) {
          clearIndicators();
          dropTargetIndex = idx;
          if (indicators[idx]) indicators[idx].classList.add('active');
        }
      });

      list.addEventListener('dragleave', function(e) {
        if (!list.contains(e.relatedTarget)) clearIndicators();
      });

      list.addEventListener('drop', function(e) {
        e.preventDefault();
        var src = dragSrcIndex;
        var dst = dropTargetIndex;
        clearIndicators();
        dragSrcIndex = null;
        if (src === null || dst === null) return;
        var insertAt = dst > src ? dst - 1 : dst;
        if (insertAt === src) return;
        var moved = selectedCommands.splice(src, 1)[0];
        selectedCommands.splice(insertAt, 0, moved);
        renderSelectedList();
      });
    }

    // Render saved toolbars list
    function renderSavedList() {
      var list = document.getElementById('savedList');
      
      if (savedToolbars.length === 0) {
        list.innerHTML = '<div class="empty-state"><p>No saved toolbars</p></div>';
        return;
      }

      list.innerHTML = savedToolbars.map(function(toolbar) {
        var isActive = toolbar.name === currentToolbarName;
        return '<div class="toolbar-list-item ' + (isActive ? 'active' : '') + '" data-toolbar-name="' + escapeHtml(toolbar.name) + '">' +
            '<span class="toolbar-name">' + escapeHtml(toolbar.name) + '</span>' +
            '<span class="toolbar-actions">' +
              '<button class="btn-toggle-vis" data-toolbar-name="' + escapeHtml(toolbar.name) + '" title="Show/Hide">👁</button>' +
              '<button class="btn-delete-tb" data-toolbar-name="' + escapeHtml(toolbar.name) + '" title="Delete">🗑</button>' +
            '</span>' +
          '</div>';
      }).join('');

      // Event delegation for saved toolbar list
      list.onclick = function(e) {
        var target = e.target;
        if (target.classList.contains('btn-toggle-vis')) {
          e.stopPropagation();
          toggleVisibility(target.getAttribute('data-toolbar-name'));
        } else if (target.classList.contains('btn-delete-tb')) {
          e.stopPropagation();
          deleteToolbar(target.getAttribute('data-toolbar-name'));
        } else {
          var item = target.closest('.toolbar-list-item');
          if (item) {
            loadToolbar(item.getAttribute('data-toolbar-name'));
          }
        }
      };
    }

    // Filter commands based on search
    function filterCommands() {
      renderAvailableList();
    }

    // Toggle command selection
    function toggleSelection(checkbox) {
      var cmdRef = checkbox.value;
      var command = availableCommands.find(function(c) { return c.command_ref === cmdRef; });
      
      if (checkbox.checked && command) {
        if (!selectedCommands.find(function(c) { return c.command_ref === cmdRef; })) {
          selectedCommands.push(command);
        }
      } else {
        selectedCommands = selectedCommands.filter(function(c) { return c.command_ref !== cmdRef; });
      }
      renderSelectedList();
    }

    // Add all selected commands from checkboxes
    function addSelectedCommands() {
      var checkboxes = document.querySelectorAll('#availableList input[type="checkbox"]:checked');
      checkboxes.forEach(function(cb) {
        var cmdRef = cb.value;
        var command = availableCommands.find(function(c) { return c.command_ref === cmdRef; });
        if (command && !selectedCommands.find(function(c) { return c.command_ref === cmdRef; })) {
          selectedCommands.push(command);
        }
      });
      renderSelectedList();
      
      // Uncheck all
      checkboxes.forEach(function(cb) { cb.checked = false; });
    }

    // Add a separator into the selected commands list
    function addSeparator() {
      selectedCommands.push({
        id: '__separator__',
        command_ref: '__sep_' + Date.now() + '__',
        name: '— Separator —',
        is_separator: true
      });
      renderSelectedList();
    }

    // Remove item from selection
    function removeItem(index) {
      selectedCommands.splice(index, 1);
      renderSelectedList();
    }

    // Clear all selections
    function clearSelection() {
      selectedCommands = [];
      document.getElementById('toolbarName').value = '';
      currentToolbarName = '';
      renderSelectedList();
      
      // Uncheck all
      document.querySelectorAll('#availableList input[type="checkbox"]').forEach(function(cb) {
        cb.checked = false;
      });
    }

    // Save toolbar configuration
    function saveToolbar() {
      var name = document.getElementById('toolbarName').value.trim();
      if (!name) {
        showStatus('Please enter a toolbar name', 'error');
        return;
      }
      if (selectedCommands.length === 0) {
        showStatus('Please select at least one command', 'error');
        return;
      }

      var config = {
        name: name,
        commands: selectedCommands.map(function(cmd) {
          if (cmd.is_separator) {
            return {
              id: '__separator__',
              command_ref: cmd.command_ref,
              name: '— Separator —',
              is_separator: true
            };
          }
          return {
            id: cmd.id,
            command_ref: cmd.command_ref,
            name: cmd.name,
            tooltip: cmd.tooltip,
            status_bar_text: cmd.status_bar_text,
            icon_path: cmd.icon_path,
            source_toolbar: cmd.source_toolbar,
            is_native: cmd.is_native || false,
            native_action: cmd.native_action || null
          };
        })
      };

      sketchup.save_toolbar(JSON.stringify(config));
    }

    // Load toolbar for editing
    function loadToolbar(name) {
      var toolbar = savedToolbars.find(function(t) { return t.name === name; });
      if (!toolbar) return;

      // Clear any checked checkboxes in the available list first
      document.querySelectorAll('#availableList input[type="checkbox"]').forEach(function(cb) {
        cb.checked = false;
      });

      currentToolbarName = name;
      document.getElementById('toolbarName').value = name;
      
      // Reconstruct command objects from saved data.
      // Priority:
      //   1. Stable id (32-char MD5 of icon+name+status) — works across restarts
      //   2. command_ref only for native tools (stable "native_xxx" strings)
      //   3. Fall back to saved data so the item still appears (placeholder)
      selectedCommands = toolbar.commands.map(function(cmd) {
        if (cmd.is_separator || cmd.id === '__separator__') return Object.assign({is_separator: true}, cmd);
        var byId = (cmd.id && cmd.id.length === 32)
          ? availableCommands.find(function(c) { return c.id === cmd.id; })
          : null;
        if (byId) return byId;
        // native_ refs are stable strings — safe to match directly
        if (cmd.command_ref && cmd.command_ref.indexOf('native_') === 0) {
          var byRef = availableCommands.find(function(c) { return c.command_ref === cmd.command_ref; });
          if (byRef) return byRef;
        }
        return cmd;
      });
      renderSelectedList();
      renderSavedList();
    }

    // Delete toolbar
    function deleteToolbar(name) {
      if (!confirm('Delete toolbar "' + name + '"?')) return;
      sketchup.delete_toolbar(name);
    }

    // Toggle toolbar visibility
    function toggleVisibility(name) {
      var toolbar = savedToolbars.find(function(t) { return t.name === name; });
      if (toolbar && toolbar.visible) {
        sketchup.hide_toolbar(name);
        toolbar.visible = false;
      } else {
        sketchup.show_toolbar(name);
        if (toolbar) toolbar.visible = true;
      }
    }

    // Export configuration
    function exportConfig() {
      sketchup.export_config();
    }

    // Import configuration
    function importConfig() {
      if (!confirm('Import will replace all existing toolbars. Continue?')) return;
      sketchup.import_config();
    }

    // Callback handlers from Ruby
    function saveSuccess(name) {
      showStatus('Toolbar "' + name + '" saved successfully', 'success');
      sketchup.get_saved_toolbars();
    }

    function saveError(message) {
      showStatus('Error: ' + message, 'error');
    }

    function deleteSuccess(name) {
      showStatus('Toolbar "' + name + '" deleted', 'success');
      if (currentToolbarName === name) {
        clearSelection();
      }
      sketchup.get_saved_toolbars();
    }

    function deleteError(message) {
      showStatus('Error: ' + message, 'error');
    }

    function exportSuccess(path) {
      showStatus('Exported to: ' + path, 'success');
    }

    function exportError(message) {
      showStatus('Export error: ' + message, 'error');
    }

    function importSuccess(toolbars) {
      showStatus('Imported ' + toolbars.length + ' toolbar(s)', 'success');
      updateSavedToolbars(toolbars);
    }

    function importError(message) {
      showStatus('Import error: ' + message, 'error');
    }

    function loadCommandsError(message) {
      showStatus('Loading error: ' + message, 'error');
      document.getElementById('availableList').innerHTML =
        '<div class="empty-state"><p>Error loading commands: ' + escapeHtml(message) + '</p></div>';
    }

    // Utility functions
    function escapeHtml(text) {
      if (!text) return '';
      var div = document.createElement('div');
      div.textContent = text;
      return div.innerHTML;
    }

    function showStatus(message, type) {
      var existing = document.querySelector('.status-message');
      if (existing) existing.remove();

      var status = document.createElement('div');
      status.className = 'status-message ' + type;
      status.textContent = message;
      document.body.appendChild(status);

      setTimeout(function() {
        status.remove();
      }, 3000);
    }

    // Handle dialog close
    window.addEventListener('beforeunload', function() {
      if (typeof sketchup !== 'undefined' && sketchup.dialog_closed) {
        sketchup.dialog_closed();
      }
    });
  </script>
</body>
</html>
        HTML
      end
    end
  end
end
