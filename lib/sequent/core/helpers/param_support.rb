require 'active_support'

module Sequent
  module Core
    module Helpers
      # Class to support binding from a params hash like the one from Sinatra
      #
      # You typically do not need to include this module in your classes. If you extend from
      # Sequent::Core::ValueObject, Sequent::Core::Event or Sequent::Core::BaseCommand you will
      # get this functionality for free.
      #
      module ParamSupport
        module ClassMethods
          def from_params(params = {})
            allocate.tap { |x| x.from_params(params) }
          end
        end

        # extend host class with class methods when we're included
        def self.included(host_class)
          host_class.extend(ClassMethods)
        end

        def from_params(params)
          params = HashWithIndifferentAccess.new(params)
          self.class.types.each do |attribute, type|
            value = params[attribute]

            next if value.blank?
            if type.respond_to? :from_params
              value = type.from_params(value)
            elsif type.is_a? Sequent::Core::Helpers::ArrayWithType
              value = value.map do |v|
                if type.item_type.respond_to?(:from_params)
                  type.item_type.from_params(v)
                else
                  v
                end
              end
            end
            instance_variable_set(:"@#{attribute}", value)
          end
        end

        def to_params(root)
          make_params root, as_params
        end

        def as_params
          hash = HashWithIndifferentAccess.new
          self.class.types.each do |field|
            value = self.instance_variable_get("@#{field[0]}")
            next if field[0] == "errors"
            hash[field[0]] = if value.kind_of?(Array)
                               next if value.blank?
                               value.map{|v|value_to_string(v)}
                             else
                               value_to_string(value)
                             end
          end
          hash
        end

        private

        def value_to_string(val)
          if val.is_a?(Sequent::Core::ValueObject)
            val.as_params
          elsif val.is_a? DateTime
            val.iso8601
          elsif val.is_a? Date
            val.strftime("%d-%m-%Y")
          else
            val
          end
        end

        def make_params(root, hash, memo = {})
          hash.each do |k, v|
            key = "#{root}[#{k}]"
            if v.is_a? Hash
              make_params(key, v, memo)
            elsif v.is_a?(Array) && v.first.is_a?(Hash)
              key = "#{key}[]"
              v.each { |value| make_params(key, value, memo) }
            elsif v.is_a?(Array)
              memo["#{key}[]"] = v
            else
              string_value = v.nil? ? "" : v.to_s
              if memo.has_key?(key)
                if memo[:key].is_a? Array
                  memo[key] << string_value
                else
                  memo[key] = [memo[key], string_value]
                end
              else
                memo[key] = string_value
              end
            end
          end
          memo
        end
      end
    end
  end
end
