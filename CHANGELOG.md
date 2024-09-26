# Changelog 7.x (changes since 7.1.0)

# Changelog 7.1.0 (changes since 7.0.0)

**BREAKING CHANGE**:
- Replaying all events for the view schema (using `sequent:migrate:online` and `sequent:migrate:offline`) now make use of the PostgreSQL committed transaction id (`xact_id()`) to track events that have already been replayed.  The replayed ids table (specified by the removed `Sequent::configuration.replayed_ids_table_name` option) is no longer used and can be dropped from your database.
There is no activerecord migration provided for the event store to add the `xact_id` since depending on the size of the event store you may want to take run this migration yourself. Replace `SCHEMA_NAME` with the name of the sequent schema:

```postgresql
BEGIN;
ALTER TABLE SCHEMA_NAME.event_records ADD COLUMN xact_id bigint;
COMMIT;

BEGIN;
# SET max_parallel_maintenance_workers = 8; # optionally set this depending on size of your event_records
# ALTER TABLE SCHEMA_NAME.event_records SET (parallel_workers = 8); # optionally set this depending on size of your event_records
CREATE INDEX event_records_xact_id_idx ON SCHEMA_NAME.event_records (xact_id) WHERE xact_id IS NOT NULL;
# ALTER TABLE SCHEMA_NAME.event_records RESET (parallel_workers); # optionally set this depending on size of your event_records
COMMIT;

ALTER TABLE SCHEMA_NAME.event_records ALTER COLUMN xact_id SET DEFAULT pg_current_xact_id()::text::bigint;
```
Next to this migration make sure you copy over the new `sequent_schema.rb` into your project so when you regenerate the database from scratch
in for instance your development environment you have the correct version. 

**Other notable changes**:
- The `MessageDispatcher` class has been removed.
- Instance-of routes in projectors and other message handlers now use an optimized lookup mechanism. These are the most common handlers (`on MyEvent do ... end`).
- Many optimizations were applied to the `ReplayOptimizedPostgresPersistor`:
  - Multi-value indexes are no longer supported, each column is now individually indexed. When a where clauses references multiple indexed columns all applicable indexes are used. For backwards compatibility multi-column index definitions are automatically changed to single-column indexes (one for each colum in the multi-column definition).
  - Default indexed columns can be specified when instantiating the `ReplayOptimizedPostgresPersistor`.
  - Indexed values are now automatically frozen.
  - Array matching and string/symbol matching in where-clauses now work for indexed columns as well.
  - The internal struct classes are now generated differently and these classes are no longer associated with a Ruby constant so cannot be referenced from your code.

# Changelog 7.0.0 (changes since 6.0.1)
- Added possibility `enable_autoregistration` for automatically registering all Command and EventHandlers
- In a Rails app all code will be eager loaded when `enable_autoregistration` is set to true upon sequent initialization via `Rails.autoloaders.main.eager_load(force: true)`. If other parts of your app (esp initializers) are dependent on code not being loaded yet you can ensure Sequent loads as last by renaming the initializer to e.g. `zz_sequent.rb` as Rails loads initializers in alphabetical order.

**BREAKING CHANGES**:
- Introduced `event_store_cache_event_types` as alternative for manually instantiating the EventStore yourself if you want to disable caching of event types.
- Calling `Sequent.configure` twice will now create a new instance of the configuration instead of changing the current instance. This is done to better support Rails apps and the reload functionality during development.

# Changelog 6.0.1 (changes since 6.0.0)
- Drop support for ruby < 3
- Upgraded ActiveStar
- Add support for ruby 3.2

# Changelog 6.0.0 (changes since 5.0.0)

- Changed the default type of `aggregate_id` in `sequent_schema` to `uuid` since Postgres support this for quite long.
- Added support for applications using ActiveRecord multiple database connections feature
- Improved out-of-the-box Rails support by fixing various bugs and providing Rake task to ease integration. See
  for more details: https://www.sequent.io/docs/rails-sequent.html
- Introduce `SEQUENT_ENV` instead of `RACK_ENV`. `SEQUENT_ENV` defaults to the value of `RAILS_ENV` or `RACK_ENV`.
- Introduce `Sequent.configuration.time_precision` which defaults to `ActiveSupport::JSON::Encoding.time_precision`
  which is the precision "after seconds" to store time in json format when an event is serialized.
- Custom command validations will now be translated according to the locale set by `Sequent.configuration.error_locale_resolver`

**BREAKING CHANGES**:

- Since `DateTime` is deprecated in the Ruby std lib the standard attribute `created_at` of `Event` and `Command` is now a `Time`.
  This should not be a problem when serializing an deserializing but might be breaking if you rely on the fact
  it being a `DateTime` rather than a `Time`.
- Renamed file of `Sequent::Test::WorkflowHelpers` to `workflow_helpers`. If you require this file manually you will need to update it's references
- You now must "tag" specs using `Sequent::Test::WorkflowHelpers` with the following metadata `workflows: true` to avoid collision with other specs
- Bugfix: `rake sequent:migrate:online` will now call `reset_column_information` when done. Otherwise a subsequent `sequent:migrate:offline` called in the same memory space fails.

# Changelog 5.0.0 (changes since 4.3.0)

- Introduce several advanced features for `Sequent::Core::Helpers::MessageHandler`s (ie. `Sequent::AggregateRoot`, `Sequent::Projector`, `Sequent::Workflow` and `Sequent::CommandHandler`), namely:
  - Message matching (see https://www.sequent.io/docs/concepts/advanced.html#message-matching)
  - Load time options (see https://www.sequent.io/docs/concepts/advanced.html#message-handler-load-time-options)
- `on MyEvent, MyEvent` will now raise an error stating the duplicate arguments
- `on` without arguments will now raise an error
- Declaring duplicate `attrs` will now raise an error

# Changelog 4.3.0 (changes since 4.2.0)

- Add ability to to load aggregates up until a certain point in time (use with caution)
- Support for ActiveStar 7.x
- Support for Ruby 3.1

# Changelog 4.2.0 (changes since 4.1.0)

- Various documentation fixes
- Upgrade to latest ar 6.1.4.x version
- Various setup fixes when doing `sequent new myapp`
- Improve `dry_run` feature by using real event store

# Changelog 4.1.0 (changes since 4.0)

- Improve performance when running specs by not using `descendants`
- Support for ActiveRecord 6.1.x
- Fixed some rake tasks for snapshotting (Thanks HEROGWP)
- Improve `ReplayOptimizedPostgresPersistor::Index`
- Various improvements to the database config (to use database url and aliases) (Thanks Bér Kessels)
- Allow for event upcasting
- Add rubocop

# Changelog 4.0 (changes since 3.5)

- Changed default ruby to 3.0.0 release
- Added `database_schema_directory` configuration parameter to determine where to
  find `sequent_schema.rb` and `sequent_migrations.rb`. Currently it has the same default as `database_config_directory`
- Dropped support for ruby < 2.7
- Moved to Github Actions for CI
- Allow splitting of indices and table definition in sql files
  to speed up replaying projectors

# Changes since 3.4

- Changed default ruby to latest 2.6 release
- Added support for ActiveRecord 6.0
- Added documentation for using with Rails

# Changes since 3.3

- Added [alter table](https://www.sequent.io/docs/concepts/migrations.html#2-altertable) capabilities to migrations. Useful for larger projections.
- Added `Sequent::Projector.manages_no_tables`.

# Changes since 3.2

- Introduced `strict_check_attributes_on_apply_events`. Sequent will fail when calling `apply` with unknown attributes.

# Changelog 3.2

Introduces optional `event_aggregate_id` and `event_sequence_number` columns to the `command_records` table.
This enables keeping track of events causing commands in workflows.

To add these columns to an existing event store you can use this sql to add them:

Please note these sql statements use the `uuid` type for `aggregate_id`.

```
ALTER TABLE command_records ADD COLUMN event_aggregate_id uuid;
ALTER TABLE command_records ADD COLUMN event_sequence_number integer;
CREATE INDEX CONCURRENTLY index_command_records_on_event ON command_records(event_aggregate_id, event_sequence_number);
```

# Changelog 3.1

The most notable changes are:

- Added more documentation on [https://www.sequent.io](https://www.sequent.io)
- Added support for AR 5.2
- Added rake task to support installation on existing databases

# Changelog 3.0

The most notable changes are:

- Added [extensive documentation](www.sequent.io/docs) for Sequent.
- Addition of more sophisticated way of replaying. See the documentation on how to configure.
- Dropped support for AR < 5.0
- Deprecated MigrateEvents as strategy for event migration
- Renamed Sequent::Core::BaseEventHandler to Sequent::Core::Projector
- Renamed Sequent::Core::Sessions::ActiveRecordSession to Sequent::Core::Persistors::ActiveRecordPersistor
- Renamed Sequent::Core::Sessions::ReplayEventsSession to Sequent::Core::Persistors::ReplayOptimzedPostgresPersistor

# Changelog 2.0

The most notable changes are:

## Addition of the queue-based command and event handling.

To illustrate the difference see example below:

```ruby
# command c1 results in event e1
on c1 do
  apply e1
end

# workflow: event e1 results in new command c3
on e1 do
  execute_commands(c3)
end

# main
execute_commands(c1, c2)
```

Prior to version 1.1 the order is as follows:

- `c1`
- `c3`
- `c2`
- `e1`

As you can see command `c3` is executed before `c2` although `c2` was scheduled before `c3`.

As of version 1.1 the order will be:

- `c1`
- `c2`
- `c3`
- `e1`

Commands and events are added to the queues as they occur and than handled in that order. If you have
never had workflows scheduling new commands in the foreground nothing changes. If you have used workflows
in the foreground the order will be different, so ensure your system still behaves correctly.

The `Sequent::Core::EventStore::PublishEventError` is renamed to `Sequent::Core::EventPublisher::PublishEventError`

## Global sequent config

Another possible breaking change is the way the config is setup. The sequent config now global, so some sequent classes
in the config do not take parameters anymore. You will need to change your sequent config, and will have affect
on your tests.
Please see [the docs](https://github.com/zilverline/sequent/blob/master/README.md) and the [example apps](https://github.com/zilverline/sequent-examples) for more information.

Full list of changes:

- New: Adding `TakeSnapshot` command to enable fine-grained support for snapshotting aggregates
  https://github.com/zilverline/sequent/pull/92
- Improvement: Minimize differences between test environment and normal environment
  https://github.com/zilverline/sequent/pull/93
- Bugfix: Fix query to load multiple aggregates of which one is snapshotted
  https://github.com/zilverline/sequent/pull/94
- Improvement: Speed up event query
  https://github.com/zilverline/sequent/pull/95
- New: Added `create_records` method available to `BaseEventHandlers` to insert multiple records in one go
  https://github.com/zilverline/sequent/pull/96
  https://github.com/zilverline/sequent/pull/100
- New: Added queue-based command and event publishing to ensure commands and events are handled in order they occurred
  https://github.com/zilverline/sequent/pull/97
- Improvement: Update `oj` to mimic ActiveSupport version 5. Thanks @respire!
  https://github.com/zilverline/sequent/pull/98
- Bugfixes: Fix sequent for AR => 5
  https://github.com/zilverline/sequent/pull/99
- Improvement: Global sequent config
  https://github.com/zilverline/sequent/pull/101
