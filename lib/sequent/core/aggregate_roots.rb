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

        def snapshot_version_by_type(clazz = Sequent::Core::AggregateRoot)
          base_class = clazz || Sequent::Core::AggregateRoot
          matching_aggregate_types = [base_class, *base_class.descendants].filter(&:snapshots_enabled?)
          matching_aggregate_types.to_h { |type| [type, type.snapshot_version] }
        end
      end
    end
  end
end
