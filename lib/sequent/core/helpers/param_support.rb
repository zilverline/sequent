require 'active_support'

module Sequent
  module Core
    module Helpers
      module ParamSupport
        module ClassMethods
          def from_params(params = {})
            result = allocate
            params = HashWithIndifferentAccess.new(params)
            result.attributes.each do |attribute, type|
              value = params[attribute]

              next if value.blank?
              if type.respond_to? :from_params
                value = type.from_params(value)
              elsif type.is_a? Sequent::Core::Helpers::ArrayWithType
                value = value.map { |v| type.item_type.from_params(v) }
              elsif type <= Date
                value = Date.strptime(value, "%d-%m-%Y") if value
              end
              result.instance_variable_set(:"@#{attribute}", value)
            end
            result
          end

        end
        # extend host class with class methods when we're included
        def self.included(host_class)
          host_class.extend(ClassMethods)
        end

        def to_params(root)
          make_params root, as_params
        end

        def as_params
          hash = HashWithIndifferentAccess.new
          self.class.types.each do |field|
            value = self.instance_variable_get("@#{field[0]}")
            next if field[0] == "errors"
            if value.respond_to?(:as_params) && value.kind_of?(ValueObject)
              value = value.as_params
            elsif value.kind_of?(Array)
              value = value.map { |val| val.kind_of?(ValueObject) ? val.as_params : val }
            elsif value.kind_of? Date
              value = value.strftime("%d-%m-%Y") if value
            end
            hash[field[0]] = value
          end
          hash
        end

        private
        def make_params(root, hash)
          result={}
          hash.each do |k, v|
            key = "#{root}[#{k}]"
            if v.is_a? Hash
              make_params(key, v).each do |k, v|
                result[k] = v.nil? ? "" : v.to_s
              end
            elsif v.is_a? Array
              result[key] = v
            else
              result[key] = v.nil? ? "" : v.to_s
            end
          end
          result
        end
      end
    end
  end
end
