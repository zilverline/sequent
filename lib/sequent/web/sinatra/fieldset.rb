require_relative 'tag_helper'
require_relative 'fieldset'

module Sequent
  module Web
    module Sinatra
      class Fieldset
        include Sequent::Web::Sinatra::TagHelper

        attr_reader :path, :parent

        def initialize(parent, path, params, errors, options = {})
          raise "params are empty while creating new fieldset path #{path}" unless params
          @values = params.has_key?(path) ? (params[path] || {}) : {}
          @parent = parent
          @path = path.to_s.gsub(/\W+/, '')
          @errors = errors
          @options = options
        end

        def nested(name)
          yield Fieldset.new(self, name, @values, @errors, @options)
        end

        def method_missing(method, *args, &block)
          @parent.send(method, *args)
        end

        def path_for(field_name)
          css_id @path, field_name
        end

      end

    end
  end
end
