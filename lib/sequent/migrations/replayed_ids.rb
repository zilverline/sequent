# frozen_string_literal: true

module Sequent
  module Migrations
    class ReplayedIds < Sequent::ApplicationRecord
      def self.migration_sql
        <<~SQL.chomp
          CREATE TABLE IF NOT EXISTS #{table_name} (event_id bigint NOT NULL, CONSTRAINT event_id_pk PRIMARY KEY(event_id));
        SQL
      end
    end
  end
end
