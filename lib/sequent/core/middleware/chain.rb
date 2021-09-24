module Sequent
  module Core
    module Middleware
      class Chain
        attr_reader :entries

        def initialize
          @entries = []
        end

        def add(middleware)
          @entries.push(middleware)
        end

        def invoke(*args, &invoker)
          chain = @entries.dup

          traverse_chain = lambda do
            if chain.empty?
              invoker.call
            else
              chain.shift.call(*args, &traverse_chain)
            end
          end

          traverse_chain.call
        end
      end
    end
  end
end
