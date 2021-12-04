# frozen_string_literal: true

module Sequent
  module Core
    #
    # Utility class containing all subclasses of AggregateRoot
    #
    class AggregateRoots
      class << self
        def aggregate_roots
          @aggregate_roots ||= []
        end

        def all
          aggregate_roots
        end

        def <<(aggregate_root)
          aggregate_roots << aggregate_root
        end
      end
    end
  end
end
