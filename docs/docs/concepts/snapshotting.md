---
title: Snapshotting
---

Snapshotting is an optimization where the [AggregateRoot's](aggregate-root.html) state is saved in the event stream. With snapshotting the state of an aggregate can be restored from a snapshot rather than by replaying all of its events.
In general there is no need for snapshotting when you have less than 100 Events in an AggregateRoot. By default snapshotting is turned off in Sequent.

Sequent supports snapshots on Aggregates that call `enable_snapshots` with a default threshold.

```ruby
class UserNames < Sequent::AggregateRoot
  enable_snapshots default_threshold: 100
end
```

Whenever more events are stored for an aggregate than its snapshot
threshold a record is stored in the `aggregates_that_need_snapshots`
table. You can use the rake `sequent:snapshots:take_snapshots[limit]`
task to snapshot up to `limit` highest priority aggregates.

You can schedule this task to run in the background regularly as it
will simply do nothing if there are no aggregates that need a new
snapshot.

**Important:** When you enable snapshotting you **must** delete all snapshots after each deploy. The AggregateRoot root state is dumped in the database. If there is a new version of an AggregateRoot class definition, the snapshotted state can not be loaded.
{: .notice--danger}

To delete all snapshots, you can execute `bundle exec rake sequent:snapshotting:delete_all`.
