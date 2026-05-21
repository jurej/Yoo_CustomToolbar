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
<html>
<head>
  <meta charset="UTF-8">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: #f5f5f5;
      height: 100vh;
      display: flex;
      flex-direction: column;
    }
    .header {
      background: #2c3e50;
      color: white;
      padding: 15px 20px;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    .header h1 { font-size: 18px; font-weight: 500; }
    .header-buttons button {
      background: #3498db;
      color: white;
      border: none;
      padding: 8px 16px;
      margin-left: 8px;
      border-radius: 4px;
      cursor: pointer;
      font-size: 13px;
    }
    .header-buttons button:hover { background: #2980b9; }
    .header-buttons button.import { background: #27ae60; }
    .header-buttons button.import:hover { background: #229954; }
    .header-buttons button.export { background: #e67e22; }
    .header-buttons button.export:hover { background: #d35400; }
    
    .main-content {
      flex: 1;
      display: flex;
      padding: 15px;
      gap: 15px;
      overflow: hidden;
    }
    
    .panel {
      background: white;
      border-radius: 6px;
      box-shadow: 0 1px 3px rgba(0,0,0,0.1);
      display: flex;
      flex-direction: column;
      overflow: hidden;
    }
    .panel-left { flex: 1; min-width: 300px; }
    .panel-right { flex: 1; min-width: 300px; }
    
    .panel-header {
      background: #ecf0f1;
      padding: 12px 15px;
      border-bottom: 1px solid #ddd;
    }
    .panel-header h2 {
      font-size: 14px;
      font-weight: 600;
      color: #2c3e50;
      text-transform: uppercase;
      letter-spacing: 0.5px;
    }
    
    .search-box {
      padding: 10px 15px;
      border-bottom: 1px solid #eee;
    }
    .search-box input {
      width: 100%;
      padding: 8px 12px;
      border: 1px solid #ddd;
      border-radius: 4px;
      font-size: 13px;
    }
    .search-box input:focus {
      outline: none;
      border-color: #3498db;
    }
    
    .list-container {
      flex: 1;
      overflow-y: auto;
      padding: 10px;
    }
    
    .command-item {
      display: flex;
      align-items: center;
      padding: 10px;
      border: 1px solid #e0e0e0;
      border-radius: 4px;
      margin-bottom: 6px;
      cursor: pointer;
      transition: all 0.2s;
      background: white;
    }
    .command-item:hover {
      background: #f8f9fa;
      border-color: #3498db;
    }
    .command-item.selected {
      background: #e3f2fd;
      border-color: #2196f3;
    }
    .command-item input[type="checkbox"] {
      margin-right: 8px;
      cursor: pointer;
      flex-shrink: 0;
    }
    .cmd-icon {
      width: 20px;
      height: 20px;
      margin-right: 8px;
      flex-shrink: 0;
      object-fit: contain;
    }
    .command-info { flex: 1; min-width: 0; }
    .command-name {
      font-weight: 500;
      font-size: 13px;
      color: #333;
      margin-bottom: 2px;
    }
    .command-source {
      font-size: 11px;
      color: #666;
    }
    
    .toolbar-config {
      padding: 15px;
      border-bottom: 1px solid #eee;
    }
    .toolbar-config label {
      display: block;
      font-size: 12px;
      font-weight: 600;
      color: #555;
      margin-bottom: 6px;
      text-transform: uppercase;
    }
    .toolbar-config input {
      width: 100%;
      padding: 10px;
      border: 1px solid #ddd;
      border-radius: 4px;
      font-size: 14px;
    }
    .toolbar-config input:focus {
      outline: none;
      border-color: #3498db;
    }
    
    .selected-list {
      flex: 1;
      overflow-y: auto;
      padding: 10px;
    }
    
    .selected-item {
      display: flex;
      align-items: center;
      padding: 12px;
      background: #f8f9fa;
      border: 1px solid #e0e0e0;
      border-radius: 4px;
      margin-bottom: 8px;
    }
    .selected-item .drag-handle {
      color: #999;
      margin-right: 10px;
      cursor: move;
      font-size: 16px;
    }
    .selected-item .item-icon {
      width: 20px;
      height: 20px;
      margin-right: 8px;
      flex-shrink: 0;
      object-fit: contain;
    }
    .selected-item .item-info {
      flex: 1;
      min-width: 0;
      overflow: hidden;
    }
    .selected-item .item-name {
      font-size: 13px;
      font-weight: 500;
      color: #333;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .selected-item .item-subname {
      font-size: 11px;
      color: #666;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .selected-item .remove-btn {
      color: #e74c3c;
      background: none;
      border: none;
      cursor: pointer;
      font-size: 16px;
      padding: 4px 8px;
      flex-shrink: 0;
    }
    .selected-item .remove-btn:hover { color: #c0392b; }
    .drop-indicator {
      height: 2px;
      background: #3498db;
      border-radius: 2px;
      margin: -1px 0;
      pointer-events: none;
      display: none;
    }
    .drop-indicator.active { display: block; }
    .selected-item.separator {
      background: none;
      border: none;
      border-top: 2px dashed #bbb;
      padding: 4px 8px;
      justify-content: space-between;
    }
    .selected-item.separator .sep-label {
      flex: 1;
      text-align: center;
      font-size: 11px;
      color: #aaa;
      letter-spacing: 1px;
      text-transform: uppercase;
      pointer-events: none;
    }
    
    .panel-footer {
      padding: 12px 15px;
      border-top: 1px solid #ddd;
      display: flex;
      justify-content: space-between;
    }
    .panel-footer button {
      padding: 8px 16px;
      border: none;
      border-radius: 4px;
      cursor: pointer;
      font-size: 13px;
    }
    .btn-primary {
      background: #3498db;
      color: white;
    }
    .btn-primary:hover { background: #2980b9; }
    .btn-danger {
      background: #e74c3c;
      color: white;
    }
    .btn-danger:hover { background: #c0392b; }
    .btn-secondary {
      background: #95a5a6;
      color: white;
    }
    .btn-secondary:hover { background: #7f8c8d; }
    
    .saved-toolbars {
      width: 250px;
      background: white;
      border-radius: 6px;
      box-shadow: 0 1px 3px rgba(0,0,0,0.1);
      display: flex;
      flex-direction: column;
      overflow: hidden;
    }
    
    .toolbar-list-item {
      padding: 12px 15px;
      border-bottom: 1px solid #eee;
      cursor: pointer;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    .toolbar-list-item:hover { background: #f8f9fa; }
    .toolbar-list-item.active {
      background: #e3f2fd;
      border-left: 3px solid #2196f3;
    }
    .toolbar-list-item .toolbar-name {
      font-weight: 500;
      font-size: 13px;
    }
    .toolbar-list-item .toolbar-actions button {
      background: none;
      border: none;
      cursor: pointer;
      font-size: 13px;
      padding: 2px 6px;
      margin-left: 4px;
      color: #666;
    }
    .toolbar-list-item .toolbar-actions button:hover { color: #333; }
    
    .empty-state {
      text-align: center;
      padding: 40px;
      color: #999;
    }
    .empty-state-icon {
      font-size: 48px;
      margin-bottom: 15px;
    }
    
    .status-message {
      position: fixed;
      bottom: 20px;
      right: 20px;
      padding: 12px 20px;
      border-radius: 4px;
      color: white;
      font-size: 13px;
      animation: slideIn 0.3s ease;
      z-index: 1000;
    }
    .status-message.success { background: #27ae60; }
    .status-message.error { background: #e74c3c; }
    @keyframes slideIn {
      from { transform: translateX(100%); opacity: 0; }
      to { transform: translateX(0); opacity: 1; }
    }
  </style>
</head>
<body>
  <div class="header">
    <h1>Custom Toolbar Builder</h1>
    <div class="header-buttons">
      <button class="import" onclick="importConfig()">Import</button>
      <button class="export" onclick="exportConfig()">Export</button>
    </div>
  </div>
  
  <div class="main-content">
    <div class="panel panel-left">
      <div class="panel-header">
        <h2>Available Commands</h2>
      </div>
      <div class="search-box">
        <input type="text" id="searchInput" placeholder="Search commands..." onkeyup="filterCommands()">
      </div>
      <div class="list-container" id="availableList">
        <div class="empty-state">
          <div class="empty-state-icon">⟳</div>
          <p>Loading commands...</p>
        </div>
      </div>
      <div class="panel-footer">
        <span id="availableCount">0 commands</span>
        <button class="btn-primary" onclick="addSelectedCommands()">Add Selected</button>
      </div>
    </div>
    
    <div class="panel panel-right">
      <div class="panel-header">
        <h2>Selected Commands</h2>
      </div>
      <div class="toolbar-config">
        <label>Toolbar Name</label>
        <input type="text" id="toolbarName" placeholder="Enter toolbar name...">
      </div>
      <div class="selected-list" id="selectedList">
        <div class="empty-state">
          <div class="empty-state-icon">☰</div>
          <p>Select commands from the left<br>to build your toolbar</p>
        </div>
      </div>
      <div class="panel-footer">
        <button class="btn-danger" onclick="clearSelection()">Clear All</button>
        <button class="btn-secondary" onclick="addSeparator()">+ Separator</button>
        <button class="btn-primary" onclick="saveToolbar()">Save Toolbar</button>
      </div>
    </div>
    
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
          return;
        }

        var html = '';
        for (var i = 0; i < filtered.length; i++) {
          var cmd = filtered[i];
          var iconHtml = '<img class="cmd-icon" src="' + (cmd.icon_path || DEFAULT_ICON) + '">';
          var sourceLine = (cmd.source_toolbar && cmd.source_toolbar !== 'Unknown') ? cmd.source_toolbar : '';
          html += '<div class="command-item" data-id="' + cmd.command_ref + '">' +
            '<input type="checkbox" value="' + cmd.command_ref + '" onchange="toggleSelection(this)">' +
            iconHtml +
            '<div class="command-info">' +
              (sourceLine ? '<div class="command-name">' + escapeHtml(sourceLine) + '</div>' : '') +
              '<div class="command-source">' + escapeHtml(cmd.name) + '</div>' +
            '</div>' +
          '</div>';
        }
        list.innerHTML = html;

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
          return {
            id: cmd.id,
            command_ref: cmd.command_ref,
            name: cmd.name,
            tooltip: cmd.tooltip,
            status_bar_text: cmd.status_bar_text,
            icon_path: cmd.icon_path,
            source_toolbar: cmd.source_toolbar
          };
        })
      };

      sketchup.save_toolbar(JSON.stringify(config));
    }

    // Load toolbar for editing
    function loadToolbar(name) {
      var toolbar = savedToolbars.find(function(t) { return t.name === name; });
      if (!toolbar) return;

      currentToolbarName = name;
      document.getElementById('toolbarName').value = name;
      
      // Reconstruct command objects from saved data
      selectedCommands = toolbar.commands.map(function(cmd) { return availableCommands.find(function(c) { return c.id === cmd.id; }) || cmd; });
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
