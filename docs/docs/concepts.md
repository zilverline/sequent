---
title: Concepts in Sequent
---

## AggregateRoot

An AggregateRoot is the class that encapsulates your domain or business logic. Your aggregates form the heart of your application.
In event sourcing state changes are described by [Events](#event). Everytime you want to
change the state of an object an Event must be applied. Sequent takes care of storing and
loading the events in the database. In Sequent AggregateRoot's extend from `Sequent::AggregateRoot`.

:exclamation: Important:

1. An AggregateRoot should **not depend** on the state of another AggregateRoot. The event stream
of an AggregateRoot must contain all events necessary to rebuild its state.


### Creating an AggregateRoot

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

This is the simplest form of an AggregateRoot. You can use the [AggregateRepository](#aggregaterepository) to store and
load AggregateRoots. Whenever an AggregateRoot is loaded by the AggregateRepository the Events are _replayed_ in order
of occurence. This is taken care of by Sequent so you don't have to worry about this. Internally Sequent uses a `sequence_number` to
keep track of the order in which Events occured and need to be replayed.

### Saving an AggregateRoot

To save an AggregateRoot you need to use the [AggregateRepository](#aggregaterepository). This is available
via `Sequent.configuration.aggregate_repository`. Typically you will save an AggregateRoot in your [CommandHandler](#commandhandler).

```ruby
  # Save an AggregateRoot in the event store
  Sequent.configuration.aggregate_repository.add_aggregate(User.new(Sequent.new_uuid))
```


### Loading an AggregateRoot

To access and do something with an AggregateRoot you need to load it from the database using the [AggregateRepository](#aggregaterepository).

```ruby
  # Load an AggregateRoot from the event store
  Sequent.configuration.aggregate_repository.load_aggregate(user_id)
```

### Changing an AggregateRoot

To make changes or do something useful with the AggregateRoot you need to define methods and ultimatly apply Events.

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

It is important to note that the state is set on the **on block of the Event and not in the method itself**.
We need to set it in the event blocks since when we retrieve the AggregateRoot from the event store
we want the same state. So in the method you will:


1. Execute domain logic (typically guards and/or calculating new state)
2. Apply new Events

In the event handling block you will **only set the new state**.

When you think of this it makes complete sense since over time domain logic can change, but what happened in the past did happen.
New domain logic has no influence over this.


### Deleting an AggregateRoot

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

Typically [Projectors](#projector) will respond to this type of Event by deleting or marking a Projection as deleted.

We can then add a guard to methods that check that the user is not deleted before applying events:

```ruby
class User < Sequent::AggregateRoot
  # rest of code omitted...

  def set_name(name)
    fail "User deleted" if @deleted
    apply UserNameSet, name: name
  end

end
```


:point_up: Recommendations:

1. Ensure you only apply **valid** state. We found defensive programming in your AggregateRoot to be very helpful.


## Event

An Event describes something that happened. Typically they are named in passed tense. E.g. `UserCreated`.
You can think of an Event as a simple Struct. In Sequent Events subclass from `Sequent::Event`.
By subclasses from `Sequent::Event` you get 2 extra attributes `aggregate_id` and `sequence_number`.
Both form the unique key of an Event.

For example:

```ruby
class UserNameSet < Sequent::Event
  attrs name: String
end
```

To declare attributes you need to use the `attrs` keyword and provide it with a list of key value pairs
containing the name and [Type](#types) of the attribute.

You can of course add multiple attributes to an Event

```ruby
class UserNameSet < Sequent::Event
  attrs firstname: String, lastname: String
end
```

You can also use `attrs` multiple times like

```ruby
class UserNameSet < Sequent::Event
  attrs name: String
  attrs lastname: String
end
```


The `attrs` will respect inheritance hierachies.

You can also use [ValueObject](#valueobject) in Events.

```ruby
class Name < Sequent::Core::ValueObject
  attrs firstname: String, lastname: String
end

class UserNameSet < Sequent::Event
  attrs name: Name
end
```

Out of the box Sequent provides a whole set of [Types](#types) you can use
for defining your attribtutes.

:point_up: Recommendations:

1. Keep Events small.
2. When an attribute changes use the same event.
This makes it easier to keep track of state changes for instance in Projectors or Workflows etc.
3. Keep events as flat as possible. Be cautious with using ValueObjects.

## Command

Commands form the API of your domain. They are simple data objects
with descriptive names describing the intent of your command. E.g. `CreateUser` or `SendInvoice`.
Commands inherit from `Sequent::Command`. Like [Events](#event) there can be seen as structs. Additionally
you typically add [Validations](#validations) to commands to ensure correctness. Sequent uses
[ActiveModel::Validations](http://api.rubyonrails.org/classes/ActiveModel/Validations.html)
to enable validations.

```ruby
class CreateUser < Sequent::Command
  attrs firstname: String, lastname: String
  validates_presence_of :firstname, :lastname
end
```

In building a web application you typically bind your html form to a Command. It will
then be passed into the [CommandService](#commandservice) and Sequent takes care of the rest.
When a Command is not valid a `Sequent::Core::CommandNotValid` will be raised containing the validation `errors`.

## CommandHandler

CommandHandlers respond to certain [Commands](#command). Commands handlers inherit from `Sequent::CommandHandler`.
To respond to a certain Command a CommandHandler needs to register a block containing the action to be taken.

```ruby
class UserCommandHandler < Sequent::CommandHandler
  on CreateUser do |command|
    repository.add_aggregate(User.new(
      aggregate_id: command.aggregate_id,
      firstname: command.firstname,
      lastname: command.lastname,
    ))
  end
end
```


The `Sequent::CommandHandler` exposes two convenience methods:

1) `repository`, a shorthand for Sequent.configuration.aggregate_repository
2) `do_with_aggregate`, basically a shorthand for `respository.load_aggregate`

A CommandHandler can respond to multiple commands:

```ruby
class UserCommandHandler < Sequent::CommandHandler
  on CreateUser do |command|
    repository.add_aggregate(User.new(
      aggregate_id: command.aggregate_id,
      firstname: command.firstname,
      lastname: command.lastname,
    ))
  end

  on ApplyForLicense do |command|
    do_with_aggregate(command, User) do |user|
      user.apply_for_license
    end
  end
end
```

A CommandHandler can of course communicate with mulitple [AggregateRoots](#aggregateroot).

```ruby
class UserCommandHandler < Sequent::CommandHandler
  on ApplyForLicense do |command|
    do_with_aggregate(command, User) do |user|
      license_server = repository.load_aggregate(command.license_server_id, LicenseServer)
      user.apply_for_license(license_server.generate_license_id)
    end
  end
end
```


:point_right: Tips

1) If you use rspec you can test your CommandHandler easily by including the `Sequent::Test::CommandHandlerHelpers` in your rspec config.
You can then test your CommandHandlers via the stanza:

```ruby
it 'creates a user` do
  given_command CreateUser.new(args)
  then_events UserCreated
end
```


## Projector
## Workflow
## AggregateRepository
## CommandService
## ValueObject
## Types
## Validations
