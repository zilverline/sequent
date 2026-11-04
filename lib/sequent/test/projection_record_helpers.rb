# frozen_string_literal: true

require 'rspec'

module Sequent
  module Test
    #
    # Checks that the records of projections (see +Sequent::Core::ProjectionRecord+) have no callbacks that run when
    # writing records, and no validations. These only run when a projector saves a record using the
    # +ActiveRecordPersistor+, and not when replaying or when writing records without instantiating them, so their
    # logic belongs in the projector. Callbacks that run when reading records, like +after_find+ and
    # +after_initialize+, and the callbacks ActiveRecord adds itself, for instance for associations, are fine.
    #
    #   describe 'projection records' do
    #     ActiveRecord::Base.descendants.select { |record_class| record_class < Sequent::Core::ProjectionRecord }
    #       .each do |record_class|
    #         it "#{record_class} has no write callbacks" do
    #           expect(record_class).to have_no_write_callbacks
    #         end
    #       end
    #   end
    #
    # Callbacks that must be kept anyway, for instance those added by a gem, can be allowed by method name, by a
    # regular expression matching the method name, or by the class of the validator:
    #
    #   expect(InvoiceRecord).to have_no_write_callbacks(allow: [:audit_changes, /\Aaudit_/, SomeGem::SomeValidator])
    #
    module ProjectionRecordHelpers
      READ_CALLBACK_KINDS = %i[initialize find].freeze

      # The callbacks ActiveRecord adds to the records of associations.
      ASSOCIATION_CALLBACK = /
        \A(autosave_associated_records_for|validate_associated_records_for)_
        |_collection_association\z
        |\A_ensure_no_duplicate_errors\z
      /x

      class << self
        ##
        # Describes the callbacks of +record_class+ that run when writing records, and its validations, except the
        # ones ActiveRecord adds itself and the ones in +allow+.
        def write_callbacks(record_class, allow: [])
          (record_class.__callbacks.keys - READ_CALLBACK_KINDS).flat_map do |kind|
            record_class.__callbacks[kind].filter_map do |callback|
              next if active_record_callback?(kind, callback.filter)
              next if allowed_callback?(allow, callback.filter)

              describe_callback(kind, callback)
            end
          end
        end

        private

        def active_record_callback?(kind, filter)
          return true if filter.is_a?(Symbol) && filter.match?(ASSOCIATION_CALLBACK)

          active_record_filters.fetch(kind, Set.new).include?(filter)
        end

        # The callbacks of a record class without callbacks of its own.
        def active_record_filters
          @active_record_filters ||= begin
            record_class = Class.new(ActiveRecord::Base) { self.abstract_class = true }
            record_class.__callbacks.to_h { |kind, chain| [kind, chain.to_set(&:filter)] }
          end
        end

        def allowed_callback?(allow, filter)
          allow.any? do |allowed|
            case allowed
            when Module then filter.is_a?(allowed)
            when Regexp then filter.is_a?(Symbol) && filter.match?(allowed)
            else filter == allowed
            end
          end
        end

        def describe_callback(kind, callback)
          filter = callback.filter
          return describe_validator(filter) if filter.is_a?(ActiveModel::Validator)

          # The before_commit chain only has before callbacks.
          name = kind.start_with?("#{callback.kind}_") ? kind : "#{callback.kind}_#{kind}"
          filter.is_a?(Symbol) || filter.is_a?(String) ? "#{name} #{filter}" : "#{name} (block)"
        end

        def describe_validator(validator)
          attributes = validator.respond_to?(:attributes) ? " #{validator.attributes.join(', ')}" : ''
          "#{validator.class.name}#{attributes}"
        end
      end

      RSpec::Matchers.define :have_no_write_callbacks do |allow: []|
        match do |record_class|
          @write_callbacks = ProjectionRecordHelpers.write_callbacks(record_class, allow:)
          @write_callbacks.empty?
        end

        failure_message do |record_class|
          "expected #{record_class} to have no callbacks that run when writing records or validations, since these " \
            "do not run when replaying, but it has: #{@write_callbacks.join(', ')}"
        end
      end
    end
  end
end
