module Sequent
  module Core
    module Helpers
      # A better const get (via https://www.ruby-forum.com/topic/103276)
      def self.constant_get(hierachy)
        ancestors = hierachy.split(%r/::/)
        parent = Object
        while ((child = ancestors.shift))
          klass = parent.const_get child
          parent = klass
        end
        klass
      end
    end
  end
end
