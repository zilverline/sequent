# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      # Some aggregates represent a unique external entity (e.g. a
      # user's email address or login name) and this uniqueness needs
      # to be enforced. For each unique key the returned object should
      # have an entry where the key of the entry describes the scope
      # of the constraint (e.g. `user_email` or `login_name`) and the
      # value represents the unique value. Values can be any JSON
      # value (string, object, array, etc). Note that uniqueness is
      # enforced across all aggregate types if the same scope is used.
      #
      # An `AggregateKeyNotUniqueError` is raised if a unique
      # constrained is violated when committing the events to the
      # database.
      module UniqueKeys
        module ClassMethods
          attr_reader :unique_key_definitions

          # Defines a unique key for your aggregate. Example usage:
          #
          # ```
          # unique_key :email, scope: :user_email
          # ```
          def unique_key(*attributes, scope:)
            fail ArgumentError, "'#{scope}' is not a symbol" unless scope.is_a?(Symbol)
            fail ArgumentError, 'attributes must be symbols' unless attributes.all? { |attr| attr.is_a?(Symbol) }

            @unique_key_definitions ||= {}

            fail ArgumentError, "duplicate scope '#{scope}'" if @unique_key_definitions.include?(scope)

            @unique_key_definitions[scope] = attributes
          end
        end

        # Returns the unique keys for the current instance based on
        # the `unique_key` defintions. You can also override it if you
        # need more compicated logic.
        #
        # Example return value:
        #
        # ```
        # {
        #   user_email: { email: 'bob@example.com' }
        # }
        # ```
        def unique_keys
          return {} if self.class.unique_key_definitions.nil?

          self.class.unique_key_definitions
            &.transform_values do |attributes|
              attributes.to_h { |attr| [attr, send(attr)] }.compact
            end
            &.delete_if { |_, value| value.empty? }
        end

        def self.included(host_class)
          host_class.extend(ClassMethods)
        end
      end
    end
  end
end
