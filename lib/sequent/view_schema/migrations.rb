module Sequent
  module ViewSchema
    class Migrations
      def self.versions
        fail "Define your own migrations class extends this class and that responds to self.versions"
      end

      def self.version
        fail "Define your own migrations class extends this class and that responds to self.version"
      end

      def self.projectors_between(old, new)
        versions.values_at(*Range.new(old + 1, new).to_a.map(&:to_s)).compact.flatten.uniq
      end
    end
  end
end

