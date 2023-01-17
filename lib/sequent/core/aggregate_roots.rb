# frozen_string_literal: true

module Sequent
  module Core
    #
    # Utility class containing all subclasses of AggregateRoot.
    #
    class AggregateRoots
      class << self
        def aggregate_roots
          Sequent::AggregateRoot.descendants
        end

        def all
          aggregate_roots
        end
      end
    end
  end
end
