module Sequent
  module Fixtures
    class CreateTestAggregate < Sequent::Command
    end

    class PingTestAggregate < Sequent::Command
      attrs message: String
    end

    class TestAggregateCreated < Sequent::Event
    end

    class TestAggregatePinged < Sequent::Event
      attrs message: String
    end

    class TestAggregateRoot < Sequent::AggregateRoot
      def initialize(id)
        super
        apply TestAggregateCreated
      end

      def ping(message)
        apply TestAggregatePinged, message: message
      end

      on TestAggregateCreated do
      end

      on TestAggregatePinged do |event|
        @messages ||= []
        @messages << event.message
      end
    end

    class NotifyTestAggregateCreated < Sequent::Command
      attrs test_aggregate_id: String
    end

    class NotifyTestAggregatePingReceived < Sequent::Command
      attrs test_aggregate_id: String
    end
  end
end
