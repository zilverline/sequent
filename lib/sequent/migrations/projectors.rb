module Sequent
  module Migrations
    class Projectors
      def self.versions
        fail "Define your own Sequent::Migrations::Projectors class that extends this class and implements this method"
      end

      def self.version
        fail "Define your own Sequent::Migrations::Projectors class that extends this class and implements this method"
      end

      def self.projectors_between(old, new)
        versions.values_at(*Range.new(old + 1, new).to_a.map(&:to_s)).compact.flatten.uniq
      end
    end
  end
end

