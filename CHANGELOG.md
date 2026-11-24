# Changelog 9.x

Every entry starts with a label, so an upgrade can start with what needs
to change: `Requirement:` (a new minimum version or step), `Breaking:`
(removed or renamed API, or something that now fails), `Behaviour:` (the
same API behaves differently), `Deprecated:`, `Feature:` and `Bug:`.

- Requirement: Sequent requires PostgreSQL 16.13 or later.

- Requirement: Ruby 3.4 or later (was 3.2) and ActiveRecord and
  ActiveModel 8.1.3 or later (was 7.1.3), since the older versions are
  no longer supported, the new runtime dependency `prism` and json 2.10
  or later. Ruby 4 is supported. Before 8.1.3, `insert_all!` fails on a
  view whose record class sets a primary key.

- Requirement: install and run the new event store migrations using
  `rake sequent:install:migrations` and `rake sequent:db:migrate`. They
  add the projector states, replay state, partition key changes,
  versioned snapshots, registered types and aggregate locking, and new
  versions of the SQL functions. One of them creates the `btree_gin`
  extension in the event store schema (see
  `find_aggregates_by_unique_key_containing`), so the database user
  that runs the migrations must be allowed to create it.

- Requirement: `aggregates_that_need_snapshots` stores the
  `aggregate_type_id` of its aggregate, so `register_snapshot_versions!`
  and `delete_unknown_snapshot_versions` no longer read the `aggregates`
  table, which is large in a big event store. Requires running the
  Sequent migrations.

  The migration fills the new column with one lookup in `aggregates`
  per row of `aggregates_that_need_snapshots`, in a single transaction
  that holds an exclusive lock on `aggregates_that_need_snapshots`
  until it commits. Until then, storing events that mark an aggregate
  for snapshotting, storing snapshots and the snapshotter all wait. On
  a big event store, run it during downtime, or split it: add the
  column nullable together with the new `store_aggregates` and
  `store_snapshots`, fill it in batches, then make it `NOT NULL`, add
  the foreign key and install the remaining functions.

- Breaking: `Persistor#commit` and `Projector#commit` are renamed to `flush`.
  Custom persistors must implement `flush`.

- Breaking: replaying passes the replayed events directly to the projectors
  instead of using an event publisher. `EventStore#replay_events_from_cursor`
  also takes a block that receives the events of each block, as an
  alternative to an `event_publisher`.

  Breaking for subclasses of the replayers: `with_sequent_config` is
  removed, and `replay_events` takes the projectors instead of the
  replay persistor. Create these using `replay_projectors`:

  ```ruby
  projectors = replay_projectors(replay_persistor, projector_classes)
  replay_events(get_events, projectors, &on_progress)
  ```

- Breaking: database connection management has been removed from Sequent and
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

- Breaking: creating an event, command or value object with attributes
  it does not declare always fails with an `UnknownAttributeError`, and
  the `strict_check_attributes_on_apply_events` setting is removed.
  Deserializing still ignores unknown attributes, so stored events keep
  loading.

- Breaking: the settings `enable_multiple_database_support`,
  `can_use_multiple_databases?` and `snapshot_record_class` (which had no
  effect), and the constants
  `DEFAULT_DATABASE_CONFIG_DIRECTORY`, `DEFAULT_DATABASE_SCHEMA_DIRECTORY`
  and `MIGRATIONS_CLASS_NAME` are removed, along with the database
  settings listed under the removed database connection management.
  The default `migrations_class` is `nil` instead of
  `Sequent::Migrations::Projectors`. `Support::Database.establish_connection`
  and `connect!` no longer read `database.yml`, and `ViewSchema.new` and
  `DryRun::ViewSchema.new` no longer take `db_config:`.

- Breaking: `Support::Database.with_search_path(*schemas)` quotes every
  argument as a schema name, so pass the schemas as separate arguments
  instead of one comma-separated string.

- Breaking: removed APIs that were deprecated: `UuidHelper` (`new_uuid`
  in commands and command handlers; use `Sequent.new_uuid`),
  `Helpers::Mergable` (`merge!` on commands), the `parent`, `children` and
  `origin` aliases of `EventRecord` and `CommandRecord`,
  `EventStore#replay_events` and `CommandService#remove_event_handler`.

- Breaking: `migrations_class_name` and `migrations_class_name=` are
  replaced by `migrations_class` and `migrations_class=`, which take
  the class instead of its name: `config.migrations_class_name =
  'Migrations'` becomes `config.migrations_class = Migrations`.
  `Sequent.migration_class` is replaced by `Sequent.migrations_class`,
  which is `nil` when no migrations class is configured.

- Breaking: a projector fails fast on mistakes it used to ignore:
  `Projector.on` raises an `ArgumentError` for a matcher that is not a
  class (like `has_attrs`), `manages_tables` without arguments raises
  (use `manages_no_tables`), and the persistor methods raise
  `Projector::NotManagedByThisProjector` for a record class that is not in
  `managed_tables`.

- Breaking: `SnapshotStore#mark_aggregate_for_snapshotting` requires a
  `snapshot_version:`, and `select_aggregates_for_snapshotting` returns
  `AggregateSnapshotNeeded` structs instead of aggregate ids.

- Breaking: for custom event publishers, the private
  `EventPublisher#process_event(event)` is
  `process_event(event_handlers, event)`, and the former
  `process_events`, which handled the queued events, is
  `process_events_if_not_already_processing`. A new private
  `process_events(event_handlers, events)` handles a batch of events
  and is what `ActiveProjectorsEventPublisher` overrides. The events
  queue is an `Array` instead of a `Queue`. A publisher that overrides
  the old `process_events` must override
  `process_events_if_not_already_processing` instead. A
  `ProjectorMigrationError` is raised as is instead of wrapped in a
  `PublishEventError`. `ViewSchema#replay!` moved to
  `Migrations::EventReplayer`, and its `projectors:` keyword is a required
  `projector_classes:`.

- Breaking: the support for event, command and snapshot JSON in text
  columns is removed, since the event store keeps these in jsonb
  columns since Sequent 8. `serialize_json?` and
  `EventRecord.serialize_to_json` are removed, `SerializesEvent` and
  `SerializesCommand` store the JSON as a hash, and the event store
  deserializes loaded events directly from their JSON instead of using
  the `event_record_class`, which makes loading events about 40% faster.

- Breaking: creating a record whose table has a `created_at` column
  without a `created_at` fails with a
  `Persistors::MissingCreatedAtError`, with all persistors. The
  persistors used the current time, so the record got other timestamps
  when the events were replayed. Pass the `created_at` of the event,
  which is also used as `updated_at` unless that is given.
  `create_or_update_record` no longer defaults its `created_at` to the
  current time.

- Breaking: `Sequent.configuration.time_precision` uses the current value of
  `ActiveSupport::JSON::Encoding.time_precision` when it is not set,
  instead of the value ActiveSupport had when Sequent was loaded.
  `Sequent::Configuration::DEFAULT_TIME_PRECISION` is removed.

- Breaking: the `insert_with_csv_size` argument and attribute of the
  `ReplayOptimizedPostgresPersistor` are removed, so the indices are the
  first argument of `ReplayOptimizedPostgresPersistor.new`.

- Breaking: the `transactional` method of the transaction providers is
  removed; call `transaction` instead, which custom transaction providers
  must implement. `ActiveRecordTransactionProvider#transaction` no
  longer starts a nested transaction by default, see the behaviour
  change below.

- Breaking: `sequent/test/time_comparison` is removed. It patched the
  comparison of `Time`, `DateTime` and `ActiveSupport::TimeWithZone` to
  ignore the digits beyond the `time_precision`. Specs that compare an
  event with its stored copy should create its times at the precision
  the event store keeps.

- Breaking: `==`, `eql?` and `hash` of value objects, events and
  commands are strict. Two objects are equal when they are of the same
  class and their attributes, taken from the instance variables and not
  through the readers, are strictly equal: 1 is not 1.0, a
  `HashWithIndifferentAccess` is not a `Hash`, a symbol key is not a
  string key, a hash with a default is not one without, and a
  `DateTime` is only equal to a `DateTime`. A `Time` and an
  `ActiveSupport::TimeWithZone` are equal when they are the same instant
  at full precision, and so are two `DateTime`s, where the comparison
  used to stop at the second. This affects `Set`, hash keys, `uniq` and
  comparisons in specs. Create values of the declared type, and define
  `==` on a value object that needs another equality.

- Breaking: a time precision beyond microseconds is not supported, since
  PostgreSQL keeps times to the microsecond. Setting
  `Sequent.configuration.time_precision` above 6 fails, and so does
  storing events while it is above 6, also when it is taken from
  `ActiveSupport::JSON::Encoding`.

- Breaking: the event store publishes the events as they are loaded from
  it, so projectors and workflows see the same values when the events
  are stored and when they are replayed: times truncated to the
  `time_precision`, symbols as strings and attributes cast to their
  type. Event handlers can therefore receive other values than before.
  The aggregate keeps the values it applied. Storing an event whose
  `created_at` is not a `Time` or `ActiveSupport::TimeWithZone`, such as
  a `String`, `Date` or `DateTime`, or whose `sequence_number` is not a
  positive `Integer`, fails instead of converting it. The event store also fails
  on an `aggregate_id` that is not a lowercase UUID, such as one in
  uppercase, which it used to store as its lowercase form. The test
  event store still accepts any `aggregate_id`. An event whose
  `aggregate_id` differs from that of its stream is refused, by the test
  event store and the dry run as well.

- Breaking: Sequent uses Ruby's `json` gem instead of Oj to serialize
  and load events, commands and snapshots. `Sequent::Core::Json`
  replaces `Sequent::Core::Oj`, which is deprecated (see below).
  Sequent no longer depends on Oj, and no longer
  sets `Oj.default_options`. Applications using Oj directly must depend
  on it and configure it themselves: without `mode: :rails`, `Oj.dump`
  writes a symbol key like `:foo` as `":foo"` instead of `"foo"`.
  Differences with the JSON Oj wrote and loaded:

  - Numbers in untyped values, such as in a `Hash` attribute, load as
    `Float`, also when they have more digits than a `Float` keeps. Oj
    loaded those as `BigDecimal`. `BigDecimal` attributes are written
    as strings and load as before.
  - `<`, `>`, `&`, U+2028 and U+2029 in strings are written as they
    are instead of escaped. The values are the same once loaded.
  - Times are written using `Sequent.configuration.time_precision`,
    also when it differs from ActiveSupport's, and always in ISO 8601,
    also when `ActiveSupport.use_standard_json_time_format` is disabled.
  - `Sequent::Core::Json.strict_load` fails with a `JSON::ParserError`
    on an object with a duplicate key, where Oj kept the last value.
    Stored events have none, since `jsonb` keeps one value per key, but
    other JSON loaded with it, also through `Sequent::Core::Oj`, can.
  - JSON nested more than 100 levels deep fails with a
    `JSON::NestingError`, when writing as well as when loading.

- Breaking: the handler blocks of message handlers are methods, so a
  block with more required parameters than the message raises an
  `ArgumentError`.

- Breaking: a `CHECK` constraint on the `events` table refuses a
  `sequence_number` below 1. The migration adds it `NOT VALID`, so it
  does not check the events already stored and takes its lock only
  briefly. Validate it when convenient with `ALTER TABLE
  sequent_schema.events VALIDATE CONSTRAINT
  events_sequence_number_check`, which reads every event. Requires
  running the Sequent migrations.

- Behaviour: `MessageRouter#match_message` returns a frozen empty set when no
  handler matches the message, instead of allocating a new set. This
  avoids an allocation for every message handler that does not handle
  a message, like aggregates applying events and event handlers that
  get every published event.

- Behaviour: `load_events` looks up an aggregate's events partition key first and
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

- Behaviour: `ReplayOptimizedPostgresPersistor#flush` loads the records of each
  table using `COPY`, also for small numbers of records that used to be
  inserted using one `INSERT` statement per record. Values that already
  have the Ruby class of their column type (integers, decimals, dates,
  timestamps, booleans and strings) are encoded by the C encoders of the
  `pg` gem instead of being serialized by ActiveRecord, which makes
  flushing about four times as fast. All other values are still
  serialized by ActiveRecord, so the stored values do not change.

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

- Behaviour: the `ActiveRecordPersistor` stores `created_at` as `updated_at` when
  creating a record with only `created_at`, like the
  `ReplayOptimizedPostgresPersistor` already did. Before, ActiveRecord
  set `updated_at` to the current time, so replaying a projector changed
  the `updated_at` of its records. The `ReplayOptimizedPostgresPersistor`
  no longer replaces a given `updated_at` with `created_at`, and sets the
  timestamps without a value to the current time when creating a record
  (if `record_timestamps` is enabled), like ActiveRecord does, instead of
  loading them as `NULL`.

- Behaviour: the `ActiveRecordTransactionProvider` no longer starts a
  nested transaction (savepoint) by default, so an `ActiveRecord::Rollback`
  in a command no longer only rolls back that command. Use
  `transaction(requires_new: true)` or
  `ActiveRecord::Base.transaction(requires_new: true)` for that.

- Behaviour: `after_commit` callbacks run when the database transaction
  is committed, using ActiveRecord's transaction callbacks, instead of
  when the block of the transaction provider ends.

- Behaviour: a change to the `events_partition_key` of an aggregate is
  recorded in `partition_key_changes`, and its events only move to the
  new partition when `rake sequent:aggregates:update_partition_keys[limit]`
  runs, which should be scheduled. Each run applies at most `limit`
  changes, so choose a limit that suits the number of events of your
  aggregates. Aggregates that another transaction has locked are
  skipped instead of waited for.

- Behaviour: storing events locks the aggregate row, and concurrent
  writers to the same aggregate get an optimistic locking error instead
  of a deadlock.

- Behaviour: `snapshot_default_threshold` and `snapshot_version` are
  class attributes, so subclasses of an aggregate with `enable_snapshots`
  take snapshots too.

- Behaviour: the handler blocks of message handlers are methods, so
  `return` only leaves that block instead of skipping the other handlers
  of the message.

- Behaviour: `set_autoset_ignore_attributes` applies to the class it is
  called on and its subclasses, instead of to all classes.

- Behaviour: `then_events` compares the class of each event as well as
  its payload, and reports which event does not match.

- Behaviour: the `migrate:current_version`, `check_*` and
  `abort_if_pending_migrations` rake tasks no longer create or migrate
  the view schema or the versions table.

- Behaviour: `AggregateRepository#contains_aggregate?` is also true for
  aggregates that are added but not yet committed, and `stream_exists?`
  and `events_exists?` require the stream to have events.

- Behaviour: `rake sequent:db:schema:dump` excludes the replay and
  archive schemas, and the view schema only when `migrations_class` is
  set, which it is not by default. With the defaults `db/structure.sql`
  now includes the view schema, which it never did before.

- Deprecated: `Sequent::Core::Oj` warns, once, and calls
  `Sequent::Core::Json`. Use `Sequent::Core::Json`.

- Deprecated: `set_autoset_ignore_attributes` is an alias of
  `autoset_ignore_attributes=`, which does not warn. Use
  `autoset_ignore_attributes=`.

- Deprecated: `Sequent::Test::DatabaseHelpers.maintain_test_database_schema`,
  since the view schema is created and replayed by the rake tasks and
  the background replay. It does not warn.

- Feature: a record class that includes `Sequent::Core::ProjectionRecord` can
  only be written by projectors, unless writing is allowed using
  `Sequent::Core::ProjectionWrites`. The `have_no_write_callbacks`
  matcher of `Sequent::Test::ProjectionRecordHelpers` checks that such a
  record class has no write callbacks or validations, which do not run
  when replaying. See
  [read-only records](https://www.sequent.io/docs/concepts/projector.html#read-only-records).

- Feature: message handlers (like projectors and workflows) support hooks that
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

- Feature: the `AggregateRepository` calls `invariants!` on an aggregate
  after loading it from the event store and before committing its
  uncommitted events. `AggregateRoot#invariants!` does nothing; an
  aggregate overrides it to check its state. An exception raised by
  `invariants!` is passed, with the aggregate and `:load` or
  `:commit`, to the configurable `aggregate_invariant_violation_handler`,
  which by default raises an `AggregateInvariantViolationError` with
  the aggregate type, id and phase and the original exception as its
  cause. An `InvariantsAppliedEvents` is raised when `invariants!`
  applies events.

- Feature: Sequent supports zero-downtime deployments (rolling
  upgrades). The enabled projectors are tracked in the
  `projector_states` table. Use the `ActiveProjectorsEventPublisher` as
  the `event_publisher` to enable this feature.

  Only projectors that are active process events during normal
  operation. Publishing an event fails with a
  `ProjectorIsActivatingError` while a projector is activating, and with
  a `DifferentProjectorVersionIsActiveError` when a different version
  of a projector is active. Replaying does not use an event publisher
  and does not check the projector state, since it writes to temporary
  tables until the replay is finalized.

  The version of a projector is set with `self.version = 2` in the
  projector, and defaults to the version of `migrations_class`, or 1
  when there is none.

  When an unknown projector is active all event processing is blocked.
  This allows deploying a new version while the old version of the code
  is still running and processing events. Only after executing
  `Sequent.activate_current_configuration!` does the new code start
  processing events, while the old code is blocked. At this moment
  traffic can be redirected from the old version to the new version.

  Activating the current configuration is part of the `migrate:offline`
  rake task, so the current deployment process (run online migrations,
  take old code offline, run offline migrations, start running the new
  code) keeps working as is.

  See https://sequent.io/docs/concepts/migrations.html for more
  information.

- Feature: projectors are replayed in the background, while the
  application keeps running, using `ProjectorsReplayer` and these rake
  tasks:

  - `sequent:projectors:replay:prepare[Projector,...]` creates the
    replay schema with the tables of the given projectors, or of all
    projectors.
  - `sequent:projectors:replay:replay` does the initial replay and
    `sequent:projectors:replay:catchup` replays the events stored since.
    Both take the `replay_group_target_size` and
    `number_of_replay_processes`.
  - `sequent:projectors:replay:optimize` creates the indexes, vacuums
    and analyzes the replayed tables.
  - `sequent:projectors:replay:golive` replays the remaining events and
    replaces the tables in the view schema with the replayed tables,
    moving the old ones to the archive schema.
  - `sequent:projectors:replay:all` runs prepare, replay, catchup,
    optimize, catchup and golive.
  - `sequent:projectors:replay:status` shows the replay state and
    `sequent:projectors:replay:abort` deletes the replay schema.
  - `sequent:projectors:status` shows the projector states,
    `sequent:projectors:deactivate[Projector,...]` stops projectors
    from processing events and
    `sequent:projectors:deactivate_unknown_projectors` does so for the
    projectors that are not in the configuration. Their tables stay.
  - `sequent:connect` connects to the database for your own tasks.

  It is configured using `replay_schema_name`, `archive_schema_name`,
  `projectors_replayer_after_prepare_hook`,
  `projectors_replayer_after_activate_hook` and
  `projectors_replayer_total_lock_timeout`, and projectors can manage
  tables through views. Indexes other than those that enforce a
  constraint are not created in the replay schema until `optimize`; a
  projector lists the ones its own queries need while replaying in
  `self.additional_replay_indexes`, as names or regular expressions.

  The extended statistics objects (`CREATE STATISTICS`) of the managed
  tables are kept. They are copied to the replay schema when preparing,
  so `ANALYZE` fills them before activation, and moved along with their
  tables when activating. Preparing and activating fail when a
  statistics object on a managed table lives outside the view schema;
  drop it and recreate it in the view schema before preparing the
  replay, or after activating it.

  Activating fails when a publication lists a managed table by name
  (`CREATE PUBLICATION ... FOR TABLE`). The publication would keep the
  archived table and silently stop publishing the replayed one. Remove
  the table from the publication before activating, and resynchronize
  the subscribers afterwards. Publications `FOR ALL TABLES` or `FOR
  TABLES IN SCHEMA` include the replayed tables by themselves.

  Preparing for activation and activating are refused when the view
  schema tables of the replayed projectors changed since the replay was
  prepared, since activating replaces them with the replayed tables,
  which do not have the change. Prepare the replay again instead.
  Changes to the replay schema tables are allowed. A replay prepared
  before upgrading is not checked. Requires running the Sequent
  migrations.

- Feature: to prepare for rolling upgrades of Sequent based applications the
  snapshot of an aggregate can now be versioned. This means that
  whenever the snapshot format changes you should either delete all
  snapshot on deployment of the new version (and ensure no old code is
  running, which is a current requirement) or you should increment the
  snapshot version using `enable_snapshots version: 2`. In this case the
  old version of the code will continue to use snapshot version 1 (the
  default version) while new code will only use snapshot version 2.
  The `aggregate_snapshot_versions` setting is a proc that returns the
  snapshot version for an aggregate class, by default the version of
  its `enable_snapshots`.
  `rake sequent:snapshots:delete_unknown_snapshot_versions` deletes the
  snapshots with a lower version than currently supported.

- Feature: `AggregateRepository#find_aggregates_by_unique_key_containing(scope,
  partial_key, clazz = nil)` loads every aggregate whose unique key in
  `scope` contains `partial_key`, using PostgreSQL's jsonb `@>`: a key
  `{employee_id: 'e1', period: '2024-01'}` is found by `{employee_id:
  'e1'}`. An optional block receives each matching key and decides
  which aggregates are loaded, for conditions a containment check
  cannot express. Aggregates in the repository are matched on their
  current unique keys, so an aggregate that is added but not yet
  committed is found, and one whose key changed since it was loaded is
  only found by its new key. A GIN index on the scope and key makes
  the lookup efficient. `rake sequent:install:migrations` installs the
  migration that creates it, along with the others. The index is built
  concurrently, so it does not block writes. It needs the `btree_gin`
  extension for the scope column, which the migration creates in the
  event store schema with `CREATE EXTENSION IF NOT EXISTS`;
  `btree_gin` is a trusted extension, so the database owner can create
  it.

- Feature: `AggregateRepository#find_aggregate` and
  `#find_aggregate_by_unique_key` load an aggregate, or return `nil` when
  it does not exist. `find_aggregate_by_unique_key` matches the
  aggregates in the repository on their current unique keys like
  `find_aggregates_by_unique_key_containing`.

- Feature: aggregate observers (`Sequent::AggregateObserver`, the
  `aggregate_observers` setting and the `when_event_observed` test helper)
  handle events synchronously as an aggregate applies them.

- Feature: `MessageHandler#handle_message!` raises an
  `UnhandledMessageError` when no handler handles the message.

- Feature: `execute_commands` takes a `validation_context:`, which is
  passed on to the validations of the commands.

- Feature: the transaction provider supports `before_commit` and
  `after_rollback` callbacks.

- Feature: `rake sequent:register:types` and
  `register:snapshot_versions` register the event, command and aggregate
  types and snapshot versions in the event store
  (`EventStore#register_types!`).

- Feature: `before_apply`, `after_apply` and `around_apply` hooks run code before,
  after or around each event an aggregate root applies, for example to
  check a condition that must hold before and after every change. They
  do not run when the aggregate is loaded, and take `only:` or `except:`
  with the same event classes and message matchers as `on`. See
  [hooks around applying events](https://www.sequent.io/docs/concepts/aggregate-root.html#hooks-around-applying-events).

- Feature: set `Sequent.configuration.verify_event_serialization`, for
  instance in specs, to fail when an event changes when it is stored,
  other than by truncating its times, so the domain code can be fixed.
  Set `Sequent.configuration.event_serialization_error_handler` to
  report the error instead, for instance in production, without failing
  the command.

- Bug: the `FakeTransactionProvider` of
  `Sequent::Test::WorkflowHelpers` never cleared its `after_commit`
  blocks, so a second `when_event` ran the blocks of the first again.

- Bug: `valid_date?` returns `false` for values that are not strings,
  instead of raising a `NoMethodError`.

- Bug: `rake sequent:install:migrations` gave migrations invalid
  timestamps when copying them crossed a minute.

- Bug: the migration to Sequent 8 also works when the existing tables do
  not use a `uuid` for the `aggregate_id` yet.

- Bug: resetting the column information and table name of records
  using single table inheritance during a view schema migration.

- Bug: the event that fails is logged when replaying fails.

- Bug: the `ReplayOptimizedPostgresPersistor` no longer leaves lazy
  transactions disabled on its connection. The COPY that loads the
  replayed records takes the raw connection, which made ActiveRecord
  send BEGIN and COMMIT for every later transaction on that
  connection, also for one that runs no query.

- Bug: the `ActiveRecordPersistor` set `updated_at` to the current
  time when a block given to `do_with_record`, `do_with_records` or
  `create_or_update_record` changed an existing record without setting
  `updated_at`, and when `update_record` changed a record whose
  `updated_at` was already the time of the event. A replay with the
  `ReplayOptimizedPostgresPersistor` kept the earlier `updated_at`. Block
  based updates now only change `updated_at` when it is set, so it is
  the same after a replay.

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
