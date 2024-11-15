# frozen_string_literal: true

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
          def from_params(params = {}, strict_nil_check = true)
            allocate.tap { |x| x.from_params(params, strict_nil_check) }
          end

          # Create an object based on HTTP form data
          # This differs from form_params that an empty string
          # is the same as nil since HTTP form post will send empty text fields
          def from_form_data(params = {})
            from_params(params, false)
          end
        end

        # extend host class with class methods when we're included
        def self.included(host_class)
          host_class.extend(ClassMethods)
        end

        def from_params(params, strict_nil_check = true)
          params = HashWithIndifferentAccess.new(params)
          self.class.types.each do |attribute, type|
            value = params[attribute]

            next if strict_nil_check && value.nil?
            next if !strict_nil_check && value.blank?

            if type.respond_to? :from_params
              value = type.from_params(value)
            elsif value.is_a?(Array)
              value = value.map do |v|
                if type.item_type.respond_to?(:from_params)
                  type.item_type.from_params(v, strict_nil_check)
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
            value = instance_variable_get("@#{field[0]}")
            next if field[0] == 'errors'

            hash[field[0]] = if value.is_a?(Array)
                               next if value.blank?

                               value.map { |v| value_to_string(v) }
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
          elsif val.is_a?(DateTime) || val.is_a?(Date)
            val.iso8601
          elsif val.is_a? Time
            val.iso8601(Sequent.configuration.time_precision)
          else
            val
          end
        end

        def make_params(key, enumerable, memo = {})
          case enumerable
          when Array
            enumerable.each_with_index do |object, index|
              make_params("#{key}[#{index}]", object, memo)
            end
          when Hash
            enumerable.each do |hash_key, object|
              make_params("#{key}[#{hash_key}]", object, memo)
            end
          else
            memo[key] = enumerable
          end
          memo
        end
      end
    end
  end
end
