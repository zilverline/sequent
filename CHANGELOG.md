# Changelog 9.x

- `Persistor#commit` and `Projector#commit` are renamed to `flush`.
  `commit` is a deprecated alias. Custom persistors must implement
  `flush`.

- Replaying passes the replayed events directly to the projectors
  instead of using an event publisher, so it no longer depends on
  `disable_event_handlers`. `EventStore#replay_events_from_cursor`
  takes a block that receives the events of each block.

  Breaking for subclasses of the replayers: `with_sequent_config` is
  removed, and `replay_events` takes the projectors instead of the
  replay persistor. Create these using `replay_projectors`:

  ```ruby
  projectors = replay_projectors(replay_persistor, projector_classes)
  replay_events(get_events, projectors, &on_progress)
  ```

- Bug: activating a replay flushed another instance of the
  `offline_replay_persistor_class` than the one the projectors used,
  losing the changes of persistors that buffer them.

- Message handlers can handle a batch of messages at once using
  `on_batch`. `handle_messages` passes consecutive matching messages to
  these handlers as one batch, in order with the `on` handlers, also
  for each block of replayed events.
  `handle_message` and `handle_messages` return the number of handler
  blocks invoked and take an `on_error` callable. `dispatch_message` is
  removed: use the handler hooks instead.

  ```ruby
  on_batch PostAdded do |events|
    create_records(PostRecord, events.map { |event| {aggregate_id: event.aggregate_id} })
  end
  ```

- Message handlers (like projectors and workflows) support hooks that
  run before, after or around each invocation of a handler block, for
  example to add instrumentation. The hooks are only run when a handler
  block is invoked, receive the messages it handles, and are inherited
  by subclasses:

  ```ruby
  class ApplicationProjector < Sequent::Projector
    self.abstract_class = true

    around_handler :instrument

    def instrument(messages)
      Instrumenter.instrument("#{messages.first.class}.#{self.class}") { yield }
    end
  end
  ```

  An `around_handler` hook skips the handler block by not continuing.
  Prefer these hooks over overriding `dispatch_message`.

- Replaying projectors keeps the extended statistics objects
  (`CREATE STATISTICS`) of the managed tables. They are copied to the
  replay schema when preparing, so `ANALYZE` fills them before
  activation, and moved along with their tables when activating.
  Before, `pg_dump --table` left them out of the replay schema and
  `ALTER TABLE ... SET SCHEMA` left them behind on the archived tables.
  Preparing and activating fail when a statistics object on a managed
  table lives outside the view schema; drop it and recreate it in the
  view schema before preparing the replay, or after activating it.

- Activating a replay fails when a publication lists a managed table
  by name (`CREATE PUBLICATION ... FOR TABLE`). The publication would
  keep the archived table and silently stop publishing the replayed
  one. Remove the table from the publication before activating, and
  resynchronize the subscribers afterwards.
  Publications `FOR ALL TABLES` or `FOR TABLES IN SCHEMA` include the
  replayed tables by themselves.

- `load_events` looks up an aggregate's events partition key first and
  then queries the events with that key as a parameter, so a custom
  plan can prune the events partitions while planning. It is now
  `STABLE`, which runs both queries against the same snapshot. It
  returns the snapshot and the events after it from separate
  statements, so the events come straight from the index in sequence
  number order instead of being sorted together with the snapshot.
  `load_event` loads by partition key the same way. The other read-only
  functions (`load_latest_snapshot`, `aggregates_that_need_snapshots`,
  `enrich_event_json` and `enrich_command_json`) are `STABLE` too, and
  the two `enrich_*` functions are `PARALLEL SAFE`, so queries over the
  `event_records` and `command_records` views can use parallel workers.
  Applying partition key changes skips aggregates that another
  transaction has locked instead of waiting for them.

- Sequent requires PostgreSQL 16.13 or later.

- The `AggregateRepository` calls `invariants!` on an aggregate
  after loading it from the event store and before committing its
  uncommitted events. `AggregateRoot#invariants!` does nothing; an
  aggregate overrides it to check its state. An exception raised by
  `invariants!` is passed, with the aggregate and `:load` or
  `:commit`, to the configurable `aggregate_invariant_violation_handler`,
  which by default raises an `AggregateInvariantViolationError` with
  the aggregate type, id and phase and the original exception as its
  cause. An `InvariantsAppliedEvents` is raised when `invariants!`
  applies events.

- Sequent now supports zero-downtime deployments (rolling
  upgrades). To enable this feature you must use the
  `ActiveProjectorsEventPublisher` to ensure events are only published
  to active projectors with the correct projector version number. Rake
  tasks are provided to prepare, replay, and activate projectors. See
  https://sequent.io/docs/concepts/migrations.html for more
  information.

- Database connection management has been removed from Sequent and
  must be provided by the hosting application. This is done
  automatically by Rails and can be done using the
  `sinatra-activerecord` gem if you are using Sinatra.

  Otherwise you can add code like:

  ```ruby
  ActiveRecord::Base.configurations = YAML.load_file(
    'db/database.yml',
    aliases: true,
  )
  ActiveRecord::Base.establish_connection(Sequent.env&.to_sym)
  ```

  The Sequent configuration options `database_config_directory`,
  `database_schema_directory`, `primary_database_key`, and
  `primary_database_role` have been removed.

- To prepare for rolling upgrades of Sequent based applications the
  snapshot of an aggregate can now be versioned. This means that
  whenever the snapshot format changes you should either delete all
  snapshot on deployment of the new version (and ensure no old code is
  running, which is a current requirement) or you should increment the
  snapshot version using `enable_snapshots version: 2`. In this case the
  old version of the code will continue to use snapshot version 1 (the
  default version) while new code will only use snapshot version 2.

- Also in preperation of rolling upgrades the enabled projectors are
  now tracked in the `projector_states` table. Use the
  `ActiveProjectorsEventPublisher` as the `event_publisher` to enable
  this feature.

  Only projectors that are active will process events during normal
  operation. Events that are published while a newer projector is
  activating or active will fail with a
  `DifferentProjectorVersionIsActiveError` error. Event replay uses
  the normal `EventPublisher` which does not check for projector
  state, since replaying will write to temporary tables until replay
  is finalized

  When an unknown projector is active all event processing will be
  blocked. This allows deploying a new version while the old version
  of the code is still running and processing events. Only after
  executing `Sequent#activate_current_configuration!` will the new
  code start processing events, while the old code is blocked. At this
  moment traffic can be redirected from the old version to the new
  version.

  Activating the current configuration is part of the
  `migrate:offline` rake task, so the current deployment process (run
  online migrations, take old code offline, run offline migrations,
  start running the new code) will keep working as is.

- `AggregateRepository#find_aggregates_by_unique_key_containing(scope,
  partial_key, clazz = nil)` loads every aggregate whose unique key in
  `scope` contains `partial_key`, using PostgreSQL's jsonb `@>`: a key
  `{employee_id: 'e1', period: '2024-01'}` is found by `{employee_id:
  'e1'}`. An optional block receives each matching key and decides
  which aggregates are loaded, for conditions a containment check
  cannot express. A GIN index on the scope and key makes the lookup
  efficient; copy the migration at
  `db/migrate/20260925120000_sequent_index_aggregate_unique_keys_by_scope_and_key.rb`
  to create it. The index is built concurrently, so it does not block
  writes. It needs the `btree_gin` extension for the scope column,
  which the migration creates in the event store schema; `btree_gin` is
  a trusted extension, so the database owner can create it.

- `AggregateRepository#find_aggregate_by_unique_key` and
  `#find_aggregates_by_unique_key_containing` also match the
  aggregates in the repository on their current unique keys. An
  aggregate that is added but not yet committed is now found, and one
  whose key changed since it was loaded is only found by its new key.

- `ReplayOptimizedPostgresPersistor#commit` loads the records of each
  table using `COPY`, also for small numbers of records that used to be
  inserted using one `INSERT` statement per record. Values that already
  have the Ruby class of their column type (integers, decimals, dates,
  timestamps, booleans and strings) are encoded by the C encoders of the
  `pg` gem instead of being serialized by ActiveRecord, which makes
  committing about four times as fast. All other values are still
  serialized by ActiveRecord, so the stored values do not change. The
  `insert_with_csv_size` argument is no longer used and is deprecated.

  A column without a value whose default the database computes (like a
  serial column, including `id`, or a default of `now()`) is left out of
  the `COPY`, so the database computes its value, like ActiveRecord
  does. Records that leave out different columns are loaded using a
  `COPY` per set of columns, in a single transaction per table; usually
  all records of a table leave out the same columns. Before, these
  columns were loaded as `NULL`, except for `id`, which was always left
  out, also when it had a value. A computed column updated to `nil` by
  the persistor is loaded as `NULL`, like ActiveRecord updates it. Specs
  check that the persistors store the same values, and document where
  they differ, like on views.

- The `ActiveRecordPersistor` stores `created_at` as `updated_at` when
  creating a record with only `created_at`, like the
  `ReplayOptimizedPostgresPersistor` already did. Before, ActiveRecord
  set `updated_at` to the current time, so replaying a projector changed
  the `updated_at` of its records. The `ReplayOptimizedPostgresPersistor`
  no longer replaces a given `updated_at` with `created_at`, and sets the
  timestamps without a value to the current time when creating a record
  (if `record_timestamps` is enabled), like ActiveRecord does, instead of
  loading them as `NULL`.

# Changelog 8.2.1

- Bug: Fix resetting column information and table_name when using Single Table Inheritance.
- Improvement: Fail fast when passing a non managed_table to the Persistor
- Improvement: Log current event when replaying fails

# Changelog 8.2.0

- The sequent gem now uses ActiveRecord migrations to handle the
  `sequent_schema`. The `view_schema` is still handled by sequent
  itself. You can install the sequent migrations in your project by
  running `rake sequent:install:migrations` which will copy the
  necessary files to your `db/migrate` directory.

  After upgrading Sequent you can run this task again to install any
  updates for the schema.

- There is a new rake task `sequent:migrate:unique_keys` which allows
  you to migrate aggregates when you change an aggregate's unique
  keys. The task loads each aggregate (optionally filtered by the
  type) from history, and updates the associated unique keys.

# Changelog 8.1.1

- Revert type id assignment changes as it introduces potential
  deadlocks when new types are added. If you already aplied the
  changes in release 8.1.0 you will have to execute the following
  SQL when upgrading:

  ```sql
  SET search_path TO sequent_schema;
  ALTER TABLE aggregate_types ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY;
  ALTER TABLE command_types ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY;
  ALTER TABLE event_types ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY;

  SELECT setval('aggregate_types_id_seq', COALESCE((SELECT MAX(id) + 1 FROM aggregate_types), 1), false);
  SELECT setval('command_types_id_seq', COALESCE((SELECT MAX(id) + 1 FROM command_types), 1), false);
  SELECT setval('event_types_id_seq', COALESCE((SELECT MAX(id) + 1 FROM event_types), 1), false);
  ```

# Changelog 8.1.0 (changes since 8.0.2)

- Support specifying unique keys for aggregates that are checked when
  transaction is committed, reducing the need for having aggregates to
  ensure uniqueness or relying on projectors. See
  lib/sequent/core/helpers/unique_keys.rb for details.

  This feature requires a new database, you can find an example
  migration at `db/migrate/20250108162754_aggregate_unique_keys.rb`.
- `CommandHandlerHelpers` has been updated to:
  - Load aggregates using the `given_events` so that unique keys can
    be tested. This may require changing your test to correctly set up
    the given events.
  - Run your test using the real or fake event store.
  - Use RSpec matchers in `then_events`.
  - `then_events` now only checks the events since the last
    `when_command` call occurred.
- You can now retrieve the current position of the event store using
  `EventStore#position_mark` and load all the events since this
  position using `EventStore#load_events_since_marked_position`. This
  is used by `CommandHandlerHelpers` but in the future might have
  other uses (such as tailing the event store as events are being
  committed).
- Use `max(id) + 1` query to assign type ids to avoid exhausing the
  SMALLINT range. Sequences are not rolled back when a transaction is
  aborted so type ids may become exhausted. This is mainly a problem
  in development when running tests, but could occur in production if
  a transaction that adds a new type is buggy and gets rolled back
  multiple times.

  Re-apply the `sequent_pgsql.sql` file to your Sequent schema to
  apply this fix.

# Changelog 8.0.2 (changes since 8.0.1)

- Add support for ActiveRecord 8. Thanks evsasse.
- Improvements for internal testing of Sequent.

# Changelog 8.0.1 (changes since 8.0.0)

- Fix Sequent CLI

# Changelog 8.0.0 (changes since 7.2.0)

- Check the [upgrade guide](https://sequent.io/docs/upgrade-guide.html)
  for upgrading an existing application using Sequent < 8.
- Sequent now requires at least Ruby 3.2, ActiveRecord 7.1, and
  PostgreSQL 14.
- The internal database schema has been re-organized to support table
  partitioning so the events of related aggregates can be stored
  together. Partitioning is optional. You can override the
  `AggregateRoot#events_partition_key` method to return the partition
  key of an aggregate that will be used by PostgreSQL to store the
  events in the correct partition.
- Storage logic of Sequent is now done by PostgreSQL stored
  procedures. This reduces the number of round-trips necessary between
  the Ruby process and the PostgreSQL server and optimizes storage
  requirements.
- `AggregateRoot#take_snapshot!` has been replaced with
  `AggregateRoot#take_snapshot` which returns the snapshot instead of
  adding it to the uncommitted events. Snapshots can be stored using
  `EventStore#store_snapshots` method.
- The `stream_records`, `event_records`, and `command_records`
  relations are no longer tables but views on the underlying
  `aggregates`, `events`, and `commands` tables. These views take care
  of joining related tables using the correct partitioning key and
  type ids. The views are mainly for backwards compatibility with the
  `*Record` Ruby classes and can only be used for querying. For
  updates the `EventStore` (and higher-level `AggregateRepository`)
  classes should be used. New APIs have been added so there is no
  longer a need to use ActiveRecord methods directly to manage the
  event store.
- Events, commands, and snapshot are now serialized directly to a
  `JSON` or `JSONB` column. The `TEXT` column type is no longer
  supported. JSON size is minimized by extracting various repetitive
  fields (such as `aggregate_id`) into database columns.
- Snapshots are now stored into a separate `snapshot_records` table
  instead of being mixed in with events in the `events` table.  This
  also makes it possible to store snapshots without an associated
  command record. Aggregates that need snapshots are tracked in a
  separate `aggregates_that_need_snapshots` so that snapshots can be
  created more quickly by a background snapshotting process.
- The `parent`, `origin` and `children` methods of `CommandRecord` and
  `EventRecord` have been replaced by more specific methods
  (`origin_command`, `parent_event`, etc) and will always return a
  record of the appropriate type.
- Events that are updated or deleted (a rare occurrence) are archived
  into the `saved_event_records` table.
- The `id` column of `aggregates` has been removed and the primary
  key is now the `aggregate_id` column.
- The `id` column of `events` has been removed and the primary
  key are now the `aggregate_id` and `sequence_number` columns.

# Changelog 7.2.0 (changes since 7.1.1)

- Many documentation improvements.
- Other small bug fixes.

# Changelog 7.1.1 (changes since 7.1.0)

Small bugfix for metadata tables migrations. See https://github.com/zilverline/sequent/issues/418. Thanks evsasse.

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
