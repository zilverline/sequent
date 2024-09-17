---
title: Upgrade Guide
---

## Upgrade to Sequent 8.x from older versions

Sequent 8 remodels the PostgreSQL event store to allow partitioning of
the aggregates, commands, and events tables. Furthermore it contains
various storage optimizations. To migrate your older Sequent database
an example script is provided in `db/sequent_8_migration.sql` that can
be run using `psql`.

You will have to adjust this script to match your desired partitioning
setup, although the default configuration will work for many cases as
well.

To make use of partitioning you will have to adjust your aggregates by
overriding the `events_partitio_key` method to indicate in which
partition the aggregate's events should be stored. For example, if you
wish to store your events in yearly partitions you might do something
like:

```ruby
class MyAggregate < Sequent::Core::Aggregate
  def events_partition_key
    "Y#{@created_at.strftime('%y')}"
  end
end
```

The partition key should be a string that:

- is short (to optimize storage and indexing)
- put related aggregates together (e.g. based on user, time, tenant,
  client, etc).
