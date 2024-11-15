# frozen_string_literal: true

require 'active_support'
require_relative '../ext/ext'
require_relative 'array_with_type'
require_relative 'default_validators'
require_relative 'type_conversion_support'
require_relative 'date_time_validator'
require_relative 'time_validator'
require_relative 'association_validator'

module Sequent
  module Core
    module Helpers
      # Provides functionality for defining attributes with their types.
      #
      # Since our Commands and ValueObjects are not backed by a database like e.g. Rails
      # we can not infer their types. We need the types to be able to parse from and to json.
      # You typically do not need to include this module in your classes. If you extend from
      # Sequent::ValueObject, Sequent::Event or Sequent::Command you will
      # get this functionality for free.
      #
      # Example:
      #
      #   attrs name: String, age: Integer, born: Date
      #
      # Currently Sequent supports the following types:
      #
      # - String
      # - Integer
      # - Boolean
      # - Date
      # - DateTime
      # - Subclasses of Sequent::ValueObject
      # - Lists defined as `array(String)`
      # - BigDecimal
      # - Sequent::Secret
      #
      module AttributeSupport
        class UnknownAttributeError < StandardError; end

        # module containing class methods to be added
        module ClassMethods
          attr_reader :types

          # Called when this module is included or when a class which includes this module is inherited from.
          #
          # All declared attrs are merged into @types in order to prevent superfluous calculation of types in a class
          # hierarchy.
          def initialize_types
            @types = inherited_types
          end

          def attrs(args)
            validate_attrs!(args)

            @types.merge!(args)
            associations = []
            args.each do |attribute, type|
              attr_accessor attribute

              if included_modules.include?(Sequent::Core::Helpers::TypeConversionSupport)
                Sequent::Core::Helpers::DefaultValidators.for(type).add_validations_for(self, attribute)
              end

              is_array = type.instance_of?(Sequent::Core::Helpers::ArrayWithType)
              needs_validation = !is_array && included_modules.include?(ActiveModel::Validations) &&
                                 type.included_modules.include?(Sequent::Core::Helpers::AttributeSupport)

              associations << attribute if is_array || needs_validation
            end

            if included_modules.include?(ActiveModel::Validations) && associations.present?
              validates_with Sequent::Core::Helpers::AssociationValidator, associations: associations
            end
            # Generate method that sets all defined attributes based on the attrs hash.
            class_eval <<EOS
              def update_all_attributes(attrs)
                super if defined?(super)
                ensure_known_attributes(attrs)
                #{@types.map do |attribute, _|
                  "@#{attribute} = attrs[:#{attribute}]"
                end.join("\n            ")}
                self
              end
EOS

            class_eval <<EOS
               def update_all_attributes_from_json(attrs)
                 super if defined?(super)
                 #{@types.map do |attribute, type|
                   "@#{attribute} = #{type}.deserialize_from_json(attrs['#{attribute}'])"
                 end.join("\n           ")}
               end
EOS
          end

          #
          # Allows you to define something is an array of a type
          # Example:
          #
          #   attrs trainees: array(Person)
          #
          def array(type)
            ArrayWithType.new(type)
          end

          def deserialize_from_json(args)
            unless args.nil?
              obj = allocate

              upcast!(args)

              obj.update_all_attributes_from_json(args)
              obj
            end
          end

          def numeric?(object)
            true if Float(object)
          rescue StandardError
            false
          end

          def upcast(&block)
            @upcasters ||= []
            @upcasters.push(block)
          end

          private

          def inherited_types
            merged_types = is_a?(Class) && superclass.respond_to?(:types) ? superclass.types.dup : {}

            included_modules
              .select { |m| m.include? Sequent::Core::Helpers::AttributeSupport }
              .reduce(merged_types) do |memo, mod|
                memo.merge(mod.types)
              end
          end

          def upcast!(hash)
            return if @upcasters.nil?

            @upcasters.each do |upcaster|
              upcaster.call(hash)
            end
          end

          def validate_attrs!(args)
            duplicate_attrs = types.keys & args.keys

            fail ArgumentError, "Attributes already defined: #{duplicate_attrs.join(', ')}" if duplicate_attrs.any?
          end

          def inherited(subclass)
            super

            subclass.initialize_types
          end
        end

        # extend host class with class methods when we're included
        def self.included(host_class)
          host_class.extend(ClassMethods)
          host_class.initialize_types
        end

        def attributes
          hash = HashWithIndifferentAccess.new
          self.class.types.each_key do |name|
            value = instance_variable_get("@#{name}")
            hash[name] = if value.respond_to?(:attributes)
                           value.attributes
                         else
                           value
                         end
          end
          hash
        end

        def as_json(opts = {})
          hash = HashWithIndifferentAccess.new
          self.class.types.each_key do |name|
            value = instance_variable_get("@#{name}")
            hash[name] = if value.respond_to?(:as_json)
                           value.as_json(opts)
                         else
                           value
                         end
          end
          hash
        end

        def update(changes)
          self.class.new(attributes.merge(changes))
        end

        def validation_errors(prefix = nil)
          result = errors.to_hash
          self.class.types.each do |field|
            value = instance_variable_get("@#{field[0]}")
            if value.respond_to? :validation_errors
              value.validation_errors.each { |k, v| result["#{field[0]}_#{k}".to_sym] = v }
            elsif field[1].instance_of?(ArrayWithType) && value.present?
              value
                .select { |val| val.respond_to?(:validation_errors) }
                .each_with_index do |val, index|
                  val.validation_errors.each do |k, v|
                    result["#{field[0]}_#{index}_#{k}".to_sym] = v
                  end
                end
            end
          end
          prefix ? HashWithIndifferentAccess[result.map { |k, v| ["#{prefix}_#{k}", v] }] : result
        end

        def ensure_known_attributes(attrs)
          return unless Sequent.configuration.strict_check_attributes_on_apply_events

          unknowns = attrs.keys.map(&:to_s) - self.class.types.keys.map(&:to_s)
          if unknowns.any?
            fail UnknownAttributeError, "#{self.class.name} does not specify attrs: #{unknowns.join(', ')}"
          end
        end
      end
    end
  end
end
