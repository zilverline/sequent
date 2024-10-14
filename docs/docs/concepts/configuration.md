---
title: Configuration
---

When generating a new Sequent project the configuration can be found in `config/initializers/sequent.rb`.
You are free to determine your own location as long as you require the file at startup of your application.

There are many configuration options, but generally sticking to the defaults should be sufficient. With that thought in
mind this chapter is divided into 3 sections:

1. The [minimum configuration](#minimum-configuration) you need
2. [Configuration options](#frequently-used-configuration) you will likely want to change
3. The [complete overview](#complete-configuration) of options. Basically the rest.

## Minimum configuration

As a bare minimum you need:

```ruby
require './db/migrations'

Sequent.configure do |config|
  config.migrations_class_name = 'Migrations'

  # sequent >= 6.0.2
  config.enable_autoregistration = true

  # sequent < 6.0.2
  config.command_handlers = [
    YourCommandHandler.new,
    OtherCommandHandler.new,
  ]

  config.event_handlers = [
    MyProjector.new,
    MyWorkflow.new,
  ]
  # end sequent < 6.0.2

end
```

The `migration_class_name` is the name of the class used to define your Migrations. See
the [Migrations](migrations.html) chapter for an in-depth explanation.

### Autoregistration
Sequent 6.0.2 introduced autoregistration of `command_handlers` and `event_handlers` via
setting `enable_autoregistration` to `true`.
Autoregistered classes will be appended to any already manually registered `command_handlers` and `event_handlers`. If
Sequent detects duplicates it will currently fail.
When setting `enable_autoregistration` to `true` in your `initializer`
any [CommandHandlers](command-handler.html), [Projectors](projector.html) and [Workflows](workflow.html) are
automatically registered in your Sequent configuration.
When you have base classes that you don't want to have automatically registered you can
set `self.abstract_class = true` for these classes. Another option to skip autoregistration is to set
`self.skip_autoregister` to `true`.

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
If any of the CommandFilters raises an Exception, execution is aborted for all passed [Commands](command.html).

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
This should be adjusted to the capacity of your server running the Migration.

### logger

The ruby Logger used by Sequent.

## Complete configuration

For the latest configuration possibilities please check the `Sequent::Configuration` implementation.

| Option                                  | Meaning                                                                                                                       | Default Value                                                      |
|-----------------------------------------|-------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------|
| migrations_class_name                   | **Required**. The name of the [class](#minimum-configuration) containing the migrations.                                      | `'Migrations'`                                                     |
| command_handlers                        | The list of [CommandHandlers](command-handler.html)                                                                           | `[]`                                                               |
| event_handlers                          | The list of [Projectors](projector.html) and [Workflows](workflow.html)                                                       | `[]`                                                               |
| aggregate_repository                    | The [AggregateRepository](aggregate-repository.html)                                                                          | `Sequent::Core::AggregateRepository.new`                           |
| command_filters                         | The list of [CommandFilters](#commandfilters)                                                                                 | `[]`                                                               |
| command_service                         | The [CommandService](command-service.html)                                                                                    | `Sequent::Core::CommandService.new`                                |
| database_config_directory               | The directory in which db config can be found                                                                                 | `'db'`                                                             |
| database_schema_directory               | The directory in which db schema and migrations can be found                                                                  | `'db'`                                                             |
| disable_event_handlers                  | If `true` no event_handlers will be called                                                                                    | `false`                                                            |
| error_locale_resolver                   | A lambda that returns the desired locale for command validation errors                                                        | `-> { I18n.locale &#124;&#124; :en }`                              |
| event_publisher                         | The EventPublisher used by the [EventStore](event_store.html).                                                                | `Sequent::Core::EventPublisher.new`                                |
| event_record_class                      | The [class](event_store.html) mapped to the `event_records`                                                                   | `Sequent::Core::EventRecord`                                       |
| event_record_hooks_class                | The class with EventRecord life cycle hooks                                                                                   | `Sequent::Core::EventRecordHooks`                                  |
| event_store                             | The [EventStore](event_store.html)                                                                                            | `Sequent::Core::EventStore.new`                                    |
| event_store_schema_name                 | The name of the db schema in which the [EventStore](event_store.html) is installed                                            | `'sequent_schema'`                                                 |
| event_store_cache_event_types           | If the EventStore should cache event types. Set this to false when running Rails in development mode                          | true                                                               |
| migration_sql_files_directory           | The location of the sql files for [Migrations](migrations.html)                                                               | `'db/tables'`                                                      |
| number_of_replay_processes              | The [number of process](#number_of_replay_processes) used while offline migration                                             | `4`                                                                |
| offline_replay_persistor_class          | The class used to persist the `Projector`s during the offline migration part.                                                 | `Sequent::Core::Persistors::ActiveRecordPersistor`                 |
| online_replay_persistor_class           | The class used to persist the `Projector`s.                                                                                   | `Sequent::Core::Persistors::ActiveRecordPersistor`                 |
| primary_database_key                    | A symbol indicating the primary database if multiple databases are specified within the provided db_config                    | `:primary`                                                         |
| primary_database_role                   | A symbol indicating the primary database role if using multiple databases with active record                                  | `:writing`                                                         |
| snapshot_event_class                    | The event class marking something as a [Snapshot event](snapshotting.html)                                                    | `Sequent::Core::SnapshotEvent`                                     |
| stream_record_class                     | The [class](event_store.html) mapped to the `stream_records` table                                                            | `Sequent::Core::StreamRecord`                                      |
| strict_check_attributes_on_apply_events | Whether or not sequent should fail on calling `apply` with invalid attributes.                                                | `false`. Will be enabled by default in the next major release.     |
| time_precision                          | Sets the precision of encoded time values. Defaults to 3 (equivalent to millisecond precision)                                | `ActiveSupport::JSON::Encoding.time_precision`                     |
| transaction_provider                    | The transaction provider used by the [CommandService](command-service.html)                                                   | `Sequent::Core::Transactions::ActiveRecordTransactionProvider.new` |
| uuid_generator                          | The UUID Generator used. Mainly useful for testing                                                                            | `Sequent::Core::RandomUuidGenerator`                               |
| versions_table_name                     | The name of the table in which Sequent checks which [migration version](migrations.html) is currently active                  | `'sequent_versions'`                                               |
| view_schema_name                        | The name of the view_schema in which the projections are created.                                                             | `'view_schema'`                                                    |
| enable_autoregistration                 | Enable autoregistration. This will autoregister `Sequent::CommandHandler`s, `Sequent::Projector`s and `Sequent::Workflow`s    | `false`                                                            |
