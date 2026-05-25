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

          # Strategy 4: Add native SketchUp tools (C++ side, not visible to ObjectSpace)
          native_cmds = native_sketchup_commands
          seen_refs = commands.map { |c| c[:command_ref] }.to_set
          native_cmds.each do |nc|
            commands << nc unless seen_refs.include?(nc[:command_ref])
          end

          commands.sort_by { |cmd| [cmd[:source_toolbar].downcase, cmd[:name].downcase] }
        rescue => e
          []
        end
      end

      # Build synthetic command entries for native SketchUp tools.
      # Native tools are C++ objects not visible to ObjectSpace; we represent them
      # as data-only entries that are restored via Sketchup.send_action at toolbar load time.
      def self.native_sketchup_commands
        imgs = Sketchup.find_support_file('Images') || ''

        # [label, action_string_or_CMD_const, icon_basename, tooltip, status_bar_text]
        definitions = [
          # Drawing tools
          ['Line',                'selectLineTool:',            'tb_line',           'Draw lines',                    'Draw straight lines'],
          ['Arc',                 'selectArcTool:',             'tb_arc',            'Draw arcs',                     'Draw arcs by 3 points'],
          ['Freehand',            'selectFreehandTool:',        'tb_freehand',       'Draw freehand lines',           'Sketch freehand lines'],
          ['Rectangle',           'selectRectangleTool:',       'tb_rectangle',      'Draw rectangles',               'Draw rectangles'],
          ['Circle',              'selectCircleTool:',          'tb_circle',         'Draw circles',                  'Draw circles'],
          ['Polygon',             'selectPolygonTool:',         'tb_polygon',        'Draw polygons',                 'Draw polygons'],
          # Modification tools
          ['Select',              'selectSelectionTool:',       'tb_select',         'Select objects',                'Select, move, scale and rotate objects'],
          ['Erase',               'selectEraseTool:',           'tb_erase',          'Erase geometry',                'Erase edges and faces'],
          ['Move',                'selectMoveTool:',            'tb_move',           'Move/Copy objects',             'Move or copy selected objects'],
          ['Push/Pull',           'selectPushPullTool:',        'tb_pushpull',       'Push/Pull faces',               'Push and pull faces to add volume'],
          ['Rotate',              'selectRotateTool:',          'tb_rotate',         'Rotate objects',                'Rotate geometry around an axis'],
          ['Scale',               'selectScaleTool:',           'tb_scale',          'Scale objects',                 'Scale geometry'],
          ['Offset',              'selectOffsetTool:',          'tb_offset',         'Offset edges/faces',            'Offset edges or faces'],
          ['Follow Me',           'selectExtrudeTool:',         'tb_followme',       'Follow Me',                     'Extrude a face along a path'],
          ['Flip',                'selectFlipTool:',            'tb_flip',           'Flip objects',                  'Flip selected objects along an axis'],
          # Measurement
          ['Tape Measure',        'selectMeasureTool:',         'tb_measure',        'Measure distances',             'Measure distances and create guide lines'],
          ['Protractor',          'selectProtractorTool:',      'tb_protractor',     'Measure angles',                'Measure angles and create guide lines'],
          ['Dimension',           'selectDimensionTool:',       'tb_dimension',      'Add dimensions',                'Create dimension annotations'],
          ['Text Label',          'selectTextTool:',            'tb_label',          'Add text labels',               'Create text labels'],
          # Construction
          ['Axes',                'selectAxisTool:',            'tb_axes',           'Place drawing axes',            'Position the drawing axes'],
          ['Section Plane',       'selectSectionPlaneTool:',    'tb_sectionplane',   'Add section plane',             'Create section cuts through the model'],
          ['3D Text',             'select3dTextTool:',          'tb_3dtext',         'Place 3D text',                 'Place extruded 3D text'],
          # Paint
          ['Paint Bucket',        'selectPaintTool:',           'tb_paint',          'Apply materials',               'Paint faces with materials and colors'],
          # Camera
          ['Orbit',               'selectOrbitTool:',           'tb_orbit',          'Orbit the camera',              'Orbit the camera around the model'],
          ['Pan',                 'selectPanTool:',             'tb_pan',            'Pan the camera',                'Pan the camera'],
          ['Zoom',                'selectZoomTool:',            'tb_zoom',           'Zoom the camera',               'Zoom in/out'],
          ['Zoom Window',         'selectZoomWindowTool:',      'tb_zoomwindow',     'Zoom to window',                'Drag a window to zoom to that area'],
          ['Zoom Extents',        'viewZoomExtents:',           'tb_zoomextents',    'Zoom to fit model',             'Zoom to fit the entire model in view'],
          ['Previous View',       'viewUndo:',                  'tb_previousview',   'Previous view',                 'Return to previous camera position'],
          ['Next View',           'viewRedo:',                  'tb_nextview',       'Next view',                     'Go to next camera position'],
          ['Walk',                'selectWalkTool:',            'tb_walk',           'Walk through model',            'Interactively walk through the model'],
          ['Look Around',         'selectLookAroundTool:',      'tb_lookaround',     'Look around',                   'Pivot the camera in place'],
          ['Position Camera',     'selectPositionCameraTool:',  'tb_positioncamera', 'Position camera',               'Place the camera at a specific location'],
          # Standard views
          ['Top View',            'viewTop:',                   'tb_topview',        'Top view',                      'Switch to top view'],
          ['Front View',          'viewFront:',                 'tb_frontview',      'Front view',                    'Switch to front view'],
          ['Right View',          'viewRight:',                 'tb_rightview',      'Right view',                    'Switch to right view'],
          ['Back View',           'viewBack:',                  'tb_backview',       'Back view',                     'Switch to back view'],
          ['Left View',           'viewLeft:',                  'tb_leftview',       'Left view',                     'Switch to left view'],
          ['Bottom View',         'viewBottom:',                'tb_bottomview',     'Bottom view',                   'Switch to bottom view'],
          ['Isometric View',      'viewIso:',                   'tb_isoview',        'Isometric view',                'Switch to isometric view'],
          # Display modes
          ['Wireframe',           'viewWireframe:',             'tb_wireframe',      'Wireframe display',             'Display edges only'],
          ['Hidden Line',         'viewHiddenLine:',            'tb_hiddenline',     'Hidden line display',           'Display with hidden lines removed'],
          ['Shaded',              'viewShaded:',                'tb_shaded',         'Shaded display',                'Display with shaded faces'],
          ['Shaded with Textures','viewShadedTexture:',         'tb_textures',       'Shaded with textures',          'Display with textures applied'],
          ['Monochrome',          'viewMonochrome:',            'tb_monochrome',     'Monochrome display',            'Display in monochrome shaded mode'],
          ['X-Ray',               'viewTransparent:',           'tb_xray',           'X-Ray mode',                   'Toggle X-Ray transparency mode'],
          # Standard file/edit
          ['New',                 'newDocument:',               'tb_new',            'New model',                     'Create a new model'],
          ['Open',                'openDocument:',              'tb_open',           'Open model',                    'Open an existing model'],
          ['Save',                'saveDocument:',              'tb_save',           'Save model',                    'Save the current model'],
          ['Print',               'printDocument:',             'tb_print',          'Print',                         'Print the current model'],
          ['Undo',                'editUndo:',                  'tb_undo',           'Undo',                          'Undo the last action'],
          ['Redo',                'editRedo:',                  'tb_redo',           'Redo',                          'Redo the last undone action'],
          ['Cut',                 'cut:',                       'tb_cut',            'Cut',                           'Cut selected to clipboard'],
          ['Copy',                'copy:',                      'tb_copy',           'Copy',                          'Copy selected to clipboard'],
          ['Paste',               'paste:',                     'tb_paste',          'Paste',                         'Paste from clipboard'],
          ['Delete',              'editDelete:',                'tb_delete',         'Delete',                        'Delete selected'],
          # Components
          ['Make Component',      'makeUniqueComponent:',       'tb_newcomponent',   'Make Component',                'Create a component from selection'],
        ]

        ext = RUBY_PLATFORM =~ /darwin/ ? '.pdf' : '.svg'

        definitions.map do |label, action, icon_base, tooltip, status|
          icon = File.join(imgs, "#{icon_base}#{ext}").gsub('\\', '/')
          icon = '' unless File.exist?(icon)
          {
            id:             "native_#{icon_base}",
            name:           label,
            tooltip:        tooltip,
            status_bar_text: status,
            icon_path:      icon,
            source_toolbar: 'SketchUp',
            command_ref:    "native_#{icon_base}",
            is_native:      true,
            native_action:  action
          }
        end
      rescue => e
        []
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

      # Generate a stable cross-session ID for a command.
      # Uses icon path (most unique artifact) + name + status text.
      # Falls back to object_id only when no other data is available.
      def self.generate_command_id(command)
        begin
          icon = command.small_icon || command.large_icon || ''
          name = command.menu_text || command.tooltip || ''
          status = command.status_bar_text || ''
          key = if !icon.empty?
            "#{File.basename(icon)}|#{name}|#{status}"
          elsif !name.empty?
            "#{name}|#{status}|#{command.object_id}"
          else
            command.object_id.to_s
          end
          Digest::MD5.hexdigest(key)
        rescue => e
          Digest::MD5.hexdigest(command.object_id.to_s)
        end
      end

    end
  end
end
