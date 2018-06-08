---
title: Snapshotting
---

Snapshotting is an optimization where the aggregate's state is saved in the event stream. With snapshotting the state of an aggregate can be restored from a snapshot rather than by replaying all of its events.

Sequent supports snapshots on aggregates that call `enable_snapshots` with a default threshold. In general it is recommended to keep the threshold low, to surface possible snapshot bugs sooner.

```ruby
class UserNames < Sequent::AggregateRoot
  enable_snapshots default_threshold: 30
end
```

To adjust the threshold of individual aggregates you can update its `StreamRecord`.

Snapshots can be taken with a `SnapshotCommand`. For example by a Rake task.

```ruby
namespace :snapshot do
  task :take_all do
    catch (:done) do
      while true
        command_service.execute_commands Sequent::Core::SnapshotCommand.new(limit: 10)
      end
    end
  end
end
```
