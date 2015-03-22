require_relative 'form'

module Sequent
  module Web
    module Sinatra
      module FormHelpers

        def html_form(action, method=:get, options={}, &block)
          html_form_for nil, action, method, options, &block
        end

        def html_form_for(for_object, action, method=:get, options={}, &block)
          raise "Given object of class #{for_object.class} does not respond to :as_params. Are you including Sequent::Core::Helpers::ParamSupport?" if (for_object and !for_object.respond_to? :as_params)
          form = Form.new(self, for_object, action, method, options.merge(role: "form"))
          form.render(&block)
        end

      end
    end
  end
end
