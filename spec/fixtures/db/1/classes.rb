require 'active_record'

class AccountRecord < Sequent::ApplicationRecord; end
class MessageRecord < Sequent::ApplicationRecord; end

class Account < Sequent::Core::AggregateRoot; end
class AccountCreated < Sequent::Core::Event; end

class Message < Sequent::Core::AggregateRoot; end
class MessageCreated < Sequent::Core::Event; end
class MessageSet < Sequent::Core::Event
  attrs message: String
end

class AccountProjector < Sequent::Core::Projector
  manages_tables AccountRecord

  on AccountCreated do |event|
    create_record(AccountRecord, {aggregate_id: event.aggregate_id})
  end
end

class MessageProjector < Sequent::Core::Projector
  manages_tables MessageRecord

  on MessageCreated do |event|
    create_record(MessageRecord, {aggregate_id: event.aggregate_id})
  end

  on MessageSet do |event|
    update_all_records(
      MessageRecord,
      event.attributes.slice(:aggregate_id),
      event.attributes.slice(:message)
    )
  end
end
