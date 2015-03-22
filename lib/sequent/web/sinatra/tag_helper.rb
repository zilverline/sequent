module Sequent
  module Web
    module Sinatra
      module TagHelper
        def raw_checkbox(field, options={})
          id = css_id(@path, field)
          value = param_or_default(field, options[:value]) || id
          values = [value].compact
          single_tag :input, options.merge(
                             :type => "checkbox", :id => id,
                             :name => calculate_name(field),
                             :value => value, checked: (values.include?(@values[field.to_s])) ? "checked" : nil
                           )
        end

        def raw_input(field, options={})
          raw_field(field, "text", options)
        end

        def raw_password(field, options={})
          raw_field(field, "password", options)
        end

        def raw_textarea(field, options={})
          value = param_or_default(field, options[:value])

          with_closing_tag :textarea, value, {rows: "3"}.merge(options.merge(
                                                                 :id => css_id(@path, field),
                                                                 :name => calculate_name(field)
                                                               ))
        end

        def raw_hidden(field, options={})
          raw_field(field, "hidden", options)
        end

        def raw_select(field, values, options={})
          value = param_or_default(field, options[:value])
          content = ""
          Array(values).each do |val|
            id, text = id_and_text_from_value(val)
            option_values = {value: id}
            option_values.merge!(selected: "selected") if (id == value)
            option_values.merge!(disabled: "disabled") if options[:disable].try(:include?, id)
            content << tag(:option, text, option_values)
          end
          tag :select, content, options.merge(:id => css_id(@path, field), :name => calculate_name(field))
        end

        def calculate_name(field)
          reverse_names = tree_in_names(field)
          "#{reverse_names.first}#{reverse_names[1..-1].map { |n| "[#{n}]" }.join}"
        end

        def full_path(field)
          tree_in_names(field).join('_')
        end

        alias_method :calculate_id, :full_path

        def tree_in_names(field)
          if respond_to? :path
            names = [field, path]
            parent = @parent
            while parent.is_a? Fieldset
              names << parent.path
              parent = parent.parent
            end
            names.reverse
          else
            [field]
          end
        end

        def param_or_default(field, default)
          @values.nil? ? default : @values.has_key?(field.to_s) ? @values[field.to_s] || default : default
        end


        def id_and_text_from_value(val)
          if val.is_a? Array
            [val[0], val[1]]
          else
            [val, val]
          end
        end

        def css_id(*things)
          things.compact.map { |t| t.to_s }.join('_').downcase.gsub(/\W/, '_')
        end

        def tag(name, content, options={})
          "<#{name.to_s}" +
            (options.length > 0 ? " #{hash_to_html_attrs(options)}" : '') +
            (content.nil? ? '>' : ">#{content}</#{name}>")
        end

        def single_tag(name, options={})
          "<#{name.to_s} #{hash_to_html_attrs(options)} />"
        end

        def with_closing_tag(name, value, options={})
          %Q{<#{name.to_s} #{hash_to_html_attrs(options)} >#{h value}</#{name.to_s}>}
        end

        def hash_to_html_attrs(options={})
          raise %Q{Keys used in options must be a Symbol. Don't use {"class" => "col-md-4"} but use {class: "col-md-4"}} if options.keys.find { |k| not k.kind_of? Symbol }
          html_attrs = ""
          options.keys.sort.each do |key|
            next if options[key].nil? # do not include empty attributes
            html_attrs << %Q(#{key}="#{h(options[key])}" )
          end
          html_attrs.chop
        end

        def merge_and_append_class_attributes(to_append, options = {})
          to_append.merge(options) do |key, oldval, newval|
            key == :class ? "#{oldval} #{newval}" : newval
          end
        end

        def i18n_name(field)
          if @path
            "#{@path}.#{field}"
          else
            field.to_s
          end
        end

        def has_form_error?(name)
          @errors.try(:has_key?, name.to_sym)
        end

        private
        def raw_field(field, field_type, options)
          value = param_or_default(field, options[:value])
          if options[:formatter]
            value = self.send(options[:formatter], value)
            options.delete(:formatter)
          end
          id = options[:id] || css_id(@path, field)
          single_tag :input, options.merge(
                             :type => field_type,
                             :id => id,
                             :name => calculate_name(field),
                             :value => value
                           )
        end


      end
    end
  end
end

