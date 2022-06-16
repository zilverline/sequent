# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      module AttrMatchers
        class ArgumentSerializer
          class << self
            def serialize_value(value, enclose_hash: false)
              return value.to_s if value.respond_to?(:matches_attr?)
              return %("#{value}") if value.is_a?(String)
              return serialize_hash(value, enclose_hash: enclose_hash) if value.is_a?(Hash)

              value
            end

            private

            def serialize_hash(hash, enclose_hash:)
              serialized = hash
                .map do |(name, value)|
                  "#{name}: #{serialize_value(value, enclose_hash: true)}"
                end
                .join(', ')

              return "{#{serialized}}" if enclose_hash

              serialized
            end
          end
        end
      end
    end
  end
end
