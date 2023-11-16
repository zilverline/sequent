# frozen_string_literal: true

module Sequent
  module Migrations
    class MigrationError < RuntimeError; end
    class MigrationNotStarted < MigrationError; end
    class MigrationDone < MigrationError; end
    class ConcurrentMigration < MigrationError; end

  end
end
