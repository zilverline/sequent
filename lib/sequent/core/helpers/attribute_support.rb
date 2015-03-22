require 'active_support'

class Symbol
  def self.deserialize_from_json(value)
    value.try(:to_sym)
  end
end

class String
  def self.deserialize_from_json(value)
    value
  end
end

class Integer
  def self.deserialize_from_json(value)
    value.blank? ? nil : value.to_i
  end
end

class Boolean
  def self.deserialize_from_json(value)
    value.nil? ? nil : (value.present? ? value : false)
  end
end

class Date
  def self.deserialize_from_json(value)
    value.nil? ? nil : Date.iso8601(value.dup)
  end
end

class DateTime
  def self.deserialize_from_json(value)
    value.nil? ? nil : DateTime.iso8601(value.dup)
  end
end

class Array
  def self.deserialize_from_json(value)
    value
  end
end

module Sequent
  module Core
    module Helpers
      module AttributeSupport
        # module containing class methods to be added
        module ClassMethods

          def types
            @types ||= {}
            if @merged_types
              @merged_types
            else
              @merged_types = is_a?(Class) && superclass.respond_to?(:types) ? @types.merge(superclass.types) : @types
              included_modules.select { |m| m.include? Sequent::Core::Helpers::AttributeSupport }.each do |mod|
                @merged_types.merge!(mod.types)
              end
              @merged_types
            end
          end

          def attrs(args)
            @types ||= {}
            @types.merge!(args)
            args.each do |attribute, _|
              attr_accessor attribute
            end

            # Generate method that sets all defined attributes based on the attrs hash.
            class_eval <<EOS
              def update_all_attributes(attrs)
                super if defined?(super)
                #{@types.map { |attribute, _|
              "@#{attribute} = attrs[:#{attribute}]"
            }.join("\n            ")}
                self
              end
EOS

            class_eval <<EOS
               def update_all_attributes_from_json(attrs)
                 super if defined?(super)
                 #{@types.map { |attribute, type|
              "@#{attribute} = #{type}.deserialize_from_json(attrs['#{attribute}'])"
            }.join("\n           ")}
               end
EOS
          end

          def array(type)
            ArrayWithType.new(type)
          end

          def deserialize_from_json(args)
            unless args.nil?
              obj = allocate()
              obj.update_all_attributes_from_json(args)
              obj
            end
          end


          def numeric?(object)
            true if Float(object) rescue false
          end

        end

        # extend host class with class methods when we're included
        def self.included(host_class)
          host_class.extend(ClassMethods)
        end


        # needed for active module JSON serialization
        def attributes
          self.class.types
        end

        def validation_errors(prefix = nil)
          result = errors.to_hash
          self.class.types.each do |field|
            value = self.instance_variable_get("@#{field[0]}")
            if value.respond_to? :validation_errors
              value.validation_errors.each { |k, v| result["#{field[0].to_s}_#{k.to_s}".to_sym] = v }
            end
          end
          prefix ? HashWithIndifferentAccess[result.map { |k, v| ["#{prefix}_#{k}", v] }] : result
        end

        def valid_date
          self.class.types.each do |name, clazz|
            if clazz == Date
              return if self.instance_variable_get("@#{name}").kind_of? Date
              unless self.instance_variable_get("@#{name}").blank?
                if (/\d{2}-\d{2}-\d{4}/ =~ self.instance_variable_get("@#{name}")).nil?
                  @errors.add(name.to_s, :invalid_date) if (/\d{2}-\d{2}-\d{4}/ =~ self.instance_variable_get("@#{name}")).nil?
                else
                  begin
                    self.instance_variable_set "@#{name}", Date.strptime(self.instance_variable_get("@#{name}"), "%d-%m-%Y")
                  rescue
                    @errors.add(name.to_s, :invalid_date)
                  end
                end
              end

            end
          end
        end

      end

      class ArrayWithType
        attr_accessor :item_type

        def initialize(item_type)
          raise "needs a item_type" unless item_type
          @item_type = item_type
        end

        def deserialize_from_json(value)
          value.nil? ? nil : value.map { |item| item_type.deserialize_from_json(item) }
        end

        def to_s
          "Sequent::Core::Helpers::ArrayWithType.new(#{item_type})"
        end
      end

    end
  end
end


