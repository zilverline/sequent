# frozen_string_literal: true

module Sequent
  module Migrations
    class Migration
      module ClassMethods
        def create(record_class, version)
          migration = new(record_class)
          migration.version = version
          migration
        end
      end

      def self.inherited(child_class)
        super
        class << child_class
          include ClassMethods
        end
      end

      attr_reader :record_class
      attr_accessor :version

      def initialize(record_class)
        @record_class = record_class
        @version = nil
      end

      def table_name
        @record_class.table_name
      end

      def copy(with_version)
        self.class.create(record_class, with_version)
      end

      def ==(other)
        return false unless other.class == self.class

        table_name == other.table_name && version == other.version
      end

      def hash
        table_name.hash + (version&.hash || 0)
      end
    end

    class AlterTable < Migration; end

    class ReplayTable < Migration; end

    module Functions
      module ClassMethods
        def alter_table(name)
          AlterTable.new(name)
        end

        def replay_table(name)
          ReplayTable.new(name)
        end

        # Short hand for Sequent::Core::Migratable.all
        def all_projectors
          Sequent::Core::Migratable.all
        end
      end

      def self.included(base)
        base.extend(ClassMethods)
      end
    end

    include Functions
  end
end
