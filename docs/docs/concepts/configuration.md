---
title: Configuration
---
When generating a new Sequent project the configuration can be found in `config/initializers/sequent.rb`.
You are free to determine your own location as long as you require the file at startup of your application.

There are many configuration options, but mostly you can stick to the defaults. With that thought in mind this
chapter is divided into 3 sections:

1. The [minimum configuration](#minimum-configuration) you need
2. [Configuration options](#frequently-used-configuration) you will likely want to change
3. The [complete overview](#complete-configuration) of options. Basically the rest.


## Minimum configuration


As a bare minimum you need:

```ruby
require './db/migrations'

Sequent.configure do |config|
 config.migrations_class_name = 'Migrations'

 config.command_handlers = [
   YourCommandHandler.new,
   OtherCommandHandler.new,
 ]

 config.event_handlers = [
   MyProjector.new,
   MyWorkflow.new,
 ]
end
```

The `migration_class_name` is the name of the class used to define your Migrations. See the [Migrations](migrations.html) chapter for an in-depth explanation.


## Frequently used configuration:

```ruby
Sequent.configure do |config|
  # minimum config omitted

  # common config options

  config.command_filters = [
    MyFilter.new,
  ]

  config.number_of_replay_processes = 4

  config.logger = Logger.new(STDOUT)
end
```

### CommandFilters

CommandFilters can be used to enforce certain criteria are met before executing commands. Typical
concerns are authorization in a user based application. A filter must implement the method `execute(command)`.
If any of the CommandFilters raises an Exception then execution is aborted for all passed [Commands](command.html).

Example

```ruby
class AdminFilter
  def execute(command)
    fail NotAnAdmin unless is_allowed?(command.user_id, command.class)
  end

  # only admin may execute admin commands
  def is_allowed?(user_id, command_class)
    return false if !UserRecord.is_admin?(user_id) && command_class <= AdminCommand
    return true
  end
end

Sequent.configure do |config|
  config.command_filters = [
    AdminFilter.new,
  ]
end
```

### number_of_replay_processes

The number of processes used to replay the events when doing a [Migration](migration.html). By default this is 4.
This should be adjusted to the capactiy of your server running the Migration.

### logger

The ruby Logger used by Sequent.

## Complete configuration

For the most recent possibilities please check the `Sequent::Configuration` implementation.

|Option|Meaning|Default Value|
|------|-------|-------------|
|aggregate_repository|The [AggregateRepository](aggregate-repository.html)|`Sequent::Core::AggregateRepository.new`|
|event_store|The [EventStore](event_store.html)|`Sequent::Core::EventStore.new`|
|command_service|The [CommandService](command-service.html)|`Sequent::Core::CommandService.new`|
|event_record_class|The [class](event_store.html) mapped to the `event_records`|`Sequent::Core::EventRecord`|
|stream_record_class|The [class](event_store.html) mapped to the `stream_records` table|`Sequent::Core::StreamRecord`|
|snapshot_event_class|The event class marking something as a [Snapshot event](snapshotting.html)|`Sequent::Core::SnapshotEvent`|
|event_record_hooks_class|The class with EventRecord life cycle hooks|`Sequent::Core::EventRecordHooks`|
|transaction_provider|The transaction provider used by the [CommandService](command-service.html)|`Sequent::Core::Transactions::ActiveRecordTransactionProvider.new`|
|event_publisher|The EventPublisher used by the [EventStore](event_store.html).|`Sequent::Core::EventPublisher.new`|
|command_handlers|The list of [CommandHandlers](command-handler.html)|Empty|
|command_filters|The list of [CommandFilters](#commandfilters)|Empty|
|event_handlers|The list of [Projectors](projector.html) and [Workflows](workflow.html)|Empty|
|uuid_generator|The [AggregateRepository](aggregate-repository.html). Mainly useful for testing|`false`|
|disable_event_handlers|If `true` no event_handlers will be called|`Sequent::Core::EventStore.new`|
|migration_sql_files_directory|The location of the sql files for [Migrations](migrations.html)|`db/tables`|
|view_schema_name|The name of the view_schema in which the projections are created.|`view_schema`|
|offline_replay_persistor_class|The class used to persist the the `Projector`s during the offline migration part..|`Sequent::Core::Persistors::ActiveRecordPersistor`|
|online_replay_persistor_class|The class used to persist the the `Projector`s.|`Sequent::Core::Persistors::ActiveRecordPersistor`|
|number_of_replay_processes|The [number of process](#number_of_replay_processes) used while offline migration|`4`|
|database_config_directory|The directory in which db config can be found|`db`|
|event_store_schema_name|The name of the db schema in which the [EventStore](event_store.html) is installed|`sequent_schema`|
|migrations_class_name|The name of the [class](#minimum-configuration) containing the migrations|Empty|
|versions_table_name|The name of the table in which Sequent checks which [migration version](migrations.html) is currently active|`sequent_versions`|
|replayed_ids_table_name|The name of the table in which Sequent keeps track of which events are already replayed during a [migration](migrations.html)|`sequent_replayed_ids`|
