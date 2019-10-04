---
title: AggregateRepository
---

The AggregateRepository is the interface for accessing Aggregates in the EventStore.

The AggregateRepository is typically used in [CommandHandlers](command-handler.html) to load and add [AggregateRoots](aggregate-root.html).

The AggregateRepository the Unit-Of-Work and Identity-Map patterns
to ensure each AggregateRoot is only loaded once per transaction
and that you always get the same AggregateRoot instance back.

The AggregateRepository keeps track of the Unit-Of-Work per thread,
so can be shared between threads.

This also means that if you load an AggregateRoot in two different
threads it will be two copies of that AggregateRoot. **Any changes
made to the AggregateRoot will not be synchronized between the threads**.
When both threads make changes to the AggregateRoot then, upon commit, one
of the threads will "win". The other thread will fail with a `Sequent::Core::EventStore::OptimisticLockingError`. 

When you use the `AggregateRepository` outside a CommandHandler
and therefore outside of the scope of the [CommandService][command-service.md] you need to manage
the state yourself.
{: .notice--danger}

You can access the AggregateRepository via `Sequent.aggregate_repository`

The public API of AggregateRepository:

## Adding an AggregateRoot

```ruby
Sequent.aggregate_repository.add_aggregate(..)
```

This adds the AggregateRoot in the AggregateRepository. If you
use the AggregateRepository outside a CommandHandler you need
to ensure the Unit-Of-Work is cleaned using `clear` or `clear!`

## Loading AggregateRoots

```ruby
# load single AggregateRoot by id and type
Sequent.aggregate_repository.load_aggregate('23456', Invoice)

# or multiple in single call
Sequent.aggregate_repository.load_aggregate(['65432', '23456'], Invoice)
```

The last parameter, the type of AggregateRoot, is optional. If given
it will fail if the type of the loaded AggregateRoot differs.

## Check if AggregateRoots exists

```ruby

# Will fail with AggregateNotFound if not found
Sequent.aggregate_repository.ensure_exists(aggregate_id, clazz)

# Returns true or false
Sequent.aggregate_repository.contains_aggregate(aggregate_id)

```

## Advanced usage outside the CommandService transaction

In some use cases you want read the AggregateRoots outside the transaction started by the CommandService. 
Valid use cases are for instance background [Workflows](workflow.html). When accessing the AggregateRepository in this cases you need to
manually clear the AggregateRepository or it will keep all loaded
AggregateRoots in memory.

```
# This will remove all loaded AggregateRoots from the Unit-of-Work cache
Sequent.aggregate_repository.clear

# Idem, but will fail if there are uncommitted events for an AggregateRoot
Sequent.aggregate_repository.clear!
```
