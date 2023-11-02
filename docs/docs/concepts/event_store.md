---
title: EventStore
---

The EventStore in Sequent inherits from `Sequent::Core::EventStore`.
Users of Sequent normally do not interface with the EventStore directly.
The [AggregateRepository](aggregate-repository.html)
handles access to the EventStore.

When you want to gather statistics on the EventStore, you will most likely query one of
the [tables](#tables-in-the-eventstore) either:

1. directly,
2. via the ActiveRecord class: `Sequent::Core::EventRecord` or
3. via the class you specified in your Sequent configuration by overriding `event_record_class`

## Tables in the EventStore

The initial EventStore in Sequent consists of a PostgreSQL schema containing three tables:

- [event_records](#event_records)
- [command_records](#command_records)
- [stream_records](#stream_records)

## event_records

The `event_records` table contains all [Events](event.html) that are applied in sequent. It consists of the following
columns:

| column name         | Description                                                                    |
|---------------------|--------------------------------------------------------------------------------|
| `aggregate_id`      | The id of the [AggregateRoot](aggregate-root.html) to which this Event applies |
| `sequence_number`   | The sequence number determines the order in which the events occurred          |
| `created_at`        | The datetime this event was constructed                                        |
| `event_type`        | The `class` name of the Event                                                  |
| `event_json`        | The Event serialized as json                                                   |
| `command_record_id` | The id of the `command_record` that "caused" this event                        |
| `stream_record`     | The id of the `stream_record` to which this Event belongs                      |

## command_records

The `command_records` table contains all [Commands](command.html) that are successfully executed in Sequent.

| column name             | Description                                                                                                                                                                                   |
|-------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `aggregate_id`          | The id of the Aggregate to which this command applies. This is optional since a command can also spawn multiple aggregates.                                                                   |
| `user_id`               | The id of the user that executed this command. This is also optional. If your command has a `user_id` attribute, this will be set.                                                            |
| `command_type`          | The `class` name of the Command                                                                                                                                                               |
| `command_json`          | The Command serialized as json                                                                                                                                                                |
| `created_at`            | The datetime this Command was constructed                                                                                                                                                     |
| `event_aggregate_id`    | The aggregate id of the `event_record` that "caused" this command. This is optional and is filled when a command is executed as a side effect of an event (Through workflows for instance)    |
| `event_sequence_number` | The sequence number of the `event_record` that "caused" this command. This is optional and is filled when a command is executed as a side effect of an event (Through workflows for instance) |

## stream_records

The `stream_records` table contains all AggregateRoots in the Sequent EventStore in order to
support [Snapshotting](snapshotting.html)
This table is used internally by Sequent. When you use Sequent in your project, you do not need to interface with this
table.

| column name          | Description                                                                       |
|----------------------|-----------------------------------------------------------------------------------|
| `created_at`         | The datetime the StreamRecord was constructed                                     |
| `aggregate_id`       | The id of the AggregateRoot                                                       |
| `aggregate_type`     | The `class` name of the AggregateRoot                                             |
| `snapshot_threshold` | The number of Events on an AggregateRoot as threshold for when to take a snapshot |
