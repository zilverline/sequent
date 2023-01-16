# frozen_string_literal: true

module Sequent
  module Core
    #
    # Utility class containing all subclasses of AggregateRoot.
    #
    # WARNING: This class is deprecated and will be removed in the next major release.
    # Please use Sequent::Core::AggregateRoot.descendants instead.
    #
    class AggregateRoots
      class << self
        def aggregate_roots
          ActiveSupport::Deprecation.warn(<<-MSG.squish)
            Sequent::Core::AggregateRoots is deprecated and will be removed in the next major release.

            Use Sequent::AggregateRoot.descendants instead.
          MSG

          Sequent::AggregateRoot.descendants
        end

        def all
          aggregate_roots
        end
      end
    end
  end
end
