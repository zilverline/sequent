require 'sequent/migrations/projectors'

VIEW_SCHEMA_VERSION = 1

class Migrations < Sequent::Migrations::Projectors
  def self.version
    VIEW_SCHEMA_VERSION
  end

  def self.versions
    {
      '1' => [
        PostProjector
      ]
    }
  end
end
