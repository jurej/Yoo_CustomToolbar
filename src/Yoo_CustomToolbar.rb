# frozen_string_literal: true

require 'sketchup.rb'
require 'extensions.rb'

module Yoo
  module CustomToolbar
    unless file_loaded?(__FILE__)
      ex = SketchupExtension.new('Custom Toolbar Builder', 'yoo_custom_toolbar/main')
      ex.description = 'Build custom toolbars from existing extension icons'
      ex.version     = '1.0.0'
      ex.copyright   = '2026'
      ex.creator     = 'Jure Judez'
      Sketchup.register_extension(ex, true)
      file_loaded(__FILE__)
    end
  end
end
