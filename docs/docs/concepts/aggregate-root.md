---
title: AggregateRoot
---

An AggregateRoot is the class that encapsulates your domain or business logic. Your aggregates form the heart of your application.
In event sourcing state changes are described by [Events](event.html). Everytime you want to
change the state of an object an Event must be applied. Sequent takes care of storing and
loading the events in the database. In Sequent AggregateRoot's extend from `Sequent::AggregateRoot`.

**Important**: An AggregateRoot should **not depend** on the state of other AggregateRoots. The event stream
of an AggregateRoot must contain all events necessary to rebuild its state.
{: .notice--warning}

## Creating an AggregateRoot

To create an AggregateRoot you do:

```ruby
class User < Sequent::AggregateRoot
  def initialize(id)
    super(id)
    apply UserCreated
  end

  on UserCreated do |event|
    # set initial state here
  end
end
```

This is the simplest form of an AggregateRoot. You can use the [AggregateRepository](aggregate-repository.html) to store and
load AggregateRoots. Whenever an AggregateRoot is loaded by the AggregateRepository the Events are _replayed_ in order
of occurence. This is taken care of by Sequent so you don't have to worry about this. Internally Sequent uses a `sequence_number` to
keep track of the order in which Events occured and need to be replayed.

## Saving an AggregateRoot

To save an AggregateRoot you need to use the [AggregateRepository](aggregate-repository.html). This is available
via `Sequent.aggregate_repository`. Typically you will save an AggregateRoot in your [CommandHandler](command-handler.html).

```ruby
  # Save an AggregateRoot in the event store
  Sequent.aggregate_repository.add_aggregate(
    User.new(Sequent.new_uuid)
  )
```


## Loading an AggregateRoot

To access and do something with an AggregateRoot you need to load it from the database using the [AggregateRepository](aggregate-repository.html).

```ruby
  # Load an AggregateRoot from the event store
  Sequent.aggregate_repository.load_aggregate(user_id)
```

## Changing an AggregateRoot

To make changes or do something useful with an AggregateRoot you need to define methods and ultimately apply Events.

For instance to set the name of the `User` we add to the User:

```ruby
class User < Sequent::AggregateRoot
  # rest of code omitted...

  def set_name(name)
    apply UserNameSet, name: name
  end

  on UserNameSet do |event|
    @name = name
  end
end
```

It is important to note that the state is set in the **on block of the Event and not in the method itself**.
We need to set it in the event blocks since when we load the AggregateRoot from the event store
we want the same state. So in the method you will:


1. Execute domain logic (like guards and/or calculating new state)
2. Apply new Events

In the event handling block you will **only set the new state**.

When you think of this from an event sourced point of view it makes sense.
Domain logic can change over time, but that should not affect existing Events.

## Deleting an AggregateRoot

Deleting an AggregateRoot is basically the same as changing one.


```ruby
class User < Sequent::AggregateRoot
  # rest of code omitted...

  def delete
    apply UserDeleted
  end

  on UserDeleted do
    @deleted = true
  end
end
```

[Projectors](projector.html) will respond to this type of Event by for instance deleting or marking a Projection as deleted.

We can also add guards to methods for instance to check whether a User is not deleted before applying events:

```ruby
class User < Sequent::AggregateRoot
  # rest of code omitted...

  def set_name(name)
    fail "User deleted" if @deleted
    apply UserNameSet, name: name
  end

end
```


**Recommendations:**
Ensure you only apply **valid** state. We found defensive programming in your AggregateRoot to be very helpful.
{: .notice--info}
