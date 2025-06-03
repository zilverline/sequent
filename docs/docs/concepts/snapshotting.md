---
title: Snapshotting
---

Snapshotting is an optimization where the [AggregateRoot's](aggregate-root.html) state is saved in the event stream. With snapshotting the state of an aggregate can be restored from a snapshot rather than by replaying all of its events.
In general there is no need for snapshotting when you have less than 100 Events in an AggregateRoot. By default snapshotting is turned off in Sequent.

Sequent supports snapshots on Aggregates that call `enable_snapshots` with a default threshold.

```ruby
class UserNames < Sequent::AggregateRoot
  enable_snapshots default_threshold: 100, version: 1
end
```

Whenever more events are stored for an aggregate than its snapshot
threshold a record is stored in the `aggregates_that_need_snapshots`
table. You can use the rake `sequent:snapshots:take_snapshots[limit]`
task to snapshot up to `limit` highest priority aggregates.

You can schedule this task to run in the background regularly as it
will simply do nothing if there are no aggregates that need a new
snapshot.

**Important:** The snapshot format is versioned, with the default
version being 1. If the implementation of an aggregate changes (e.g. a
new field is added, or a hash changed into an array, etc) the snapshot
format becomes incompatible and the version must be increased. This
ensures the new implementation will not try to use the old snapshot
format.

Alternatively, you can delete all snapshots whenever a new
version of your application is deployed. This will cause a temporary
drop in performance when loading previously snapshotted aggregates,
since all events will have to be reloaded and replayed when an
aggregate is accessed.

To delete all snapshots, you can execute `bundle exec rake sequent:snapshotting:delete_all`.
