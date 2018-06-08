---
title: Snapshotting
---

Snapshotting is an optimization where the [AggregateRoot's](aggregate-root.html) state is saved in the event stream. With snapshotting the state of an aggregate can be restored from a snapshot rather than by replaying all of its events.
In general there is no need for snapshotting when you have less than 100 Events in an AggregateRoot. By default snapshotting is turned off in Sequent.

Sequent supports snapshots on aggregates that call `enable_snapshots` with a default threshold

```ruby
class UserNames < Sequent::AggregateRoot
  enable_snapshots default_threshold: 100
end
```


You then also need to update the existing `StreamRecord`'s in the database to ensure they are also eligible for snapshotting.
This can be done via `bundle exec rake sequent:snapshotting:set_snapshot_threshold[Usernames,100]`.

After this snapshots can be taken with the `SnapshotCommand`. For example by a Rake task.

```ruby
namespace :snapshot do
  task :take_all do
    catch (:done) do
      while true
        Sequent.command_service.execute_commands Sequent::Core::SnapshotCommand.new(limit: 10)
      end
    end
  end
end
```

**Important:** When you enable snapshotting you **must** delete all snapshots on each deploy. The AggregateRoot root state is dumped in the database if in the new version you change the class definition the snapshotted state can not be loaded.
{: .notice--danger}

To delete all snapshots do you can execute `bundle exec rake sequent:snapshotting::delete_all`.

