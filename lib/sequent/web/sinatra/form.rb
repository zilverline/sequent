require_relative 'tag_helper'
require_relative 'fieldset'

module Sequent
  module Web
    module Sinatra
      class Form
        include TagHelper

        def initialize(context, for_object, action, method=:get, options = {})
          @context = context
          @values = params
          @errors = @context.instance_variable_get("@errors")
          @for_object = for_object
          @action = action
          @method = method
          @options = options
        end

        def path_for(field_name)
          css_id field_name
        end

        def method_missing(method, *args, &block)
          @context.send(method, *args)
        end

        def render(&block)
          method_input = ''
          if @method.is_a? Symbol
            case @method.to_s.downcase
              when 'delete', 'update'
                method_input = %Q(<input type="hidden" name="_method" value="#{@method}" />)
                @method = :post
              when 'create'
                @method = :post
            end
          end

          inner_html = capture_erb(self, &block)
          out = tag(:form, nil, {:action => @action, :method => @method.to_s.upcase}.merge(@options)) + method_input + csrf_tag
          out << inner_html
          out << '</form>'
          buf = @context.instance_variable_get("@_out_buf")
          buf << out

        end

        def fieldset(obj_name, options = {}, &block)
          raise ArgumentError, "Missing block to fieldset()" unless block_given?
          raise "can not create a fieldset without a form backing object" unless @for_object
          params.merge!(params.nil? ? {obj_name.to_s => @for_object.as_params} : params.merge({obj_name.to_s => @for_object.as_params}))
          yield Fieldset.new(@context, obj_name, HashWithIndifferentAccess.new(params), @errors, options)
        end


        private
        def capture_erb(*args, &block)
          erb_with_output_buffer { block_given? && block.call(*args) }
        end

        def erb_with_output_buffer(buf = '')
          old_buffer = @context.instance_variable_get("@_out_buf")
          @context.instance_variable_set "@_out_buf", buf
          yield
          @context.instance_variable_get("@_out_buf")
        ensure
          @context.instance_variable_set "@_out_buf", old_buffer
        end


      end

    end
  end
end

