# frozen_string_literal: true

require 'active_record'

class AccountRecord < Sequent::ApplicationRecord; end
class MessageRecord < Sequent::ApplicationRecord; end

class Account < Sequent::Core::AggregateRoot; end
class AccountCreated < Sequent::Core::Event; end

class Message < Sequent::Core::AggregateRoot; end
class MessageCreated < Sequent::Core::Event; end

class ItemRecord < ActiveRecord::Base; end
class LineItemRecord < ActiveRecord::Base; end

class MessageSet < Sequent::Core::Event
  attrs message: String
end

class AccountProjector < Sequent::Projector
  manages_tables AccountRecord

  on AccountCreated do |event|
    create_record(AccountRecord, {aggregate_id: event.aggregate_id})
  end
end

class MessageProjector < Sequent::Projector
  manages_tables MessageRecord

  on MessageCreated do |event|
    create_record(MessageRecord, {aggregate_id: event.aggregate_id})
  end

  on MessageSet do |event|
    update_all_records(
      MessageRecord,
      event.attributes.slice(:aggregate_id),
      event.attributes.slice(:message),
    )
  end
end

class ItemProjector < Sequent::Projector
  manages_tables ItemRecord, LineItemRecord
end

class BaseFooRecord < Sequent::ApplicationRecord
  self.table_name = 'foo_records'
end
class FooRecord < BaseFooRecord; end
class SpecialFooRecord < BaseFooRecord; end

class MessageWithAddedColumnCreated < Sequent::Core::Event; end
class FooProjector < Sequent::Projector
  manages_tables BaseFooRecord

  on MessageCreated do |event|
    create_record(BaseFooRecord, {aggregate_id: event.aggregate_id, type: FooRecord.name})
  end

  on MessageWithAddedColumnCreated do |event|
    create_record(BaseFooRecord, {aggregate_id: event.aggregate_id, type: FooRecord.name, description: 'foo'})
  end
end
