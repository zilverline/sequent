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
