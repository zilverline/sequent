---
title: Upgrade Guide
---

## Upgrade to Sequent 8.x from older versions

**IMPORTANT**: Ensure you are on the latest released 7.x version first.

Sequent 8 remodels the PostgreSQL event store to allow partitioning of
the aggregates, commands, and events tables. Furthermore, it contains
various storage optimizations. To migrate your older Sequent database
we advise you to **run the migration first on a copy of your production
database!** This will give you a good indication on how long the 
migration will take so you can schedule downtime appropriately.
Next to that it will ensure all data in your event store is compatible 
with Sequent 8. Normally this won't be a problem
unless you somehow have corrupted data in your event store.

To run the upgrade:
1. Update Sequent to version 8 in your Gemfile
2. Run the `bundle exec sequent migrate` command from your project directory.

This command will help you perform the database upgrade step by step 
by providing you with a default schema and database upgrade script that you can
customize to match your desired partitioning setup, although the
default configuration will work for many cases as well.

**IMPORTANT**: If the migration succeeds and you COMMIT the results
you must vacuum (e.g. using VACUUM VERBOSE ANALYZE) the new tables to
ensure good performance!

To make use of partitioning you will have to adjust your aggregates by
overriding the `events_partition_key` method to indicate in which
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
