require_relative '../../../fixtures/db/1/classes'

class SpecMigrations < Sequent::Migrations::Projectors
  DEFAULT_VERSIONS = {
    '1' => [AccountProjector, MessageProjector].freeze
  }.freeze

  @@versions = DEFAULT_VERSIONS

  DEFAULT_VERSION = 1
  @@version = DEFAULT_VERSION

  def self.versions
    @@versions
  end

  def self.copy_and_add(version, migrations)
    v = @@versions.dup
    v[version] = migrations
    self.versions = v
  end

  def self.versions=(v)
    @@versions = v
  end

  def self.version
    @@version
  end

  def self.version=(v)
    @@version = v
  end

  def self.reset
    @@versions = DEFAULT_VERSIONS
    @@version = DEFAULT_VERSION
  end
end
