---
title: Concepts in Sequent
---

## AggregateRoot

An AggregateRoot is the class that encapsulates your domain or business logic. Your aggregates form the heart of your application.
In event sourcing state changes are described by [Events](#event). Everytime you want to
change the state of an object an Event must be applied. Sequent takes care of storing and
loading the events in the database. In Sequent AggregateRoot's extend from `Sequent::AggregateRoot`.

**Important**: An AggregateRoot should **not depend** on the state of another AggregateRoot. The event stream
of an AggregateRoot must contain all events necessary to rebuild its state.
{: .notice--warning}

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
via `Sequent.aggregate_repository`. Typically you will save an AggregateRoot in your [CommandHandler](#commandhandler).

```ruby
  # Save an AggregateRoot in the event store
  Sequent.aggregate_repository.add_aggregate(
    User.new(Sequent.new_uuid)
  )
```


### Loading an AggregateRoot

To access and do something with an AggregateRoot you need to load it from the database using the [AggregateRepository](#aggregaterepository).

```ruby
  # Load an AggregateRoot from the event store
  Sequent.aggregate_repository.load_aggregate(user_id)
```

### Changing an AggregateRoot

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


1. Execute domain logic (typically guards and/or calculating new state)
2. Apply new Events

In the event handling block you will **only set the new state**.

When you think of this it makes sense, since over time domain logic can change, but what happened in the still happened.
Even if the current business logic would not allow this. So new business logic should never interfere with rebuilding the
state from past events.


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


**Recommendations:**
Ensure you only apply **valid** state. We found defensive programming in your AggregateRoot to be very helpful.
{: .notice--info}

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

<div class="notice--info">
<strong>Recommendations:</strong>
  <ul>
    <li>Keep Events small.</li>
    <li>When an attribute changes use the same event.
        This makes it easier to keep track of state changes for instance in Projectors or Workflows etc.</li>
    <li>Keep events as flat as possible. Overly nested ValueObject might seem to remove duplication, but is not always practical in usage.</li>
  </ul>
</div>

## Command

Commands form the API of your domain. They are simple data objects
with descriptive names describing the intent of your command. E.g. `CreateUser` or `SendInvoice`.
Commands inherit from `Sequent::Command`. Like [Events](#event) they can be seen as structs. Additionally
you can add [Validations](#validations) to commands to ensure correctness. Sequent uses
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

1. `repository`, a shorthand for Sequent.configuration.aggregate_repository
2. `do_with_aggregate`, basically a shorthand for `respository.load_aggregate`

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

To use CommandHandlers in your project you need to add them to the Sequent configuration

```ruby
  Sequent.configure do |config|
    config.command_handlers = [
      UserCommandHandler.new
    ]
  end
```

**Tip:** If you use rspec you can test your CommandHandler easily by including the `Sequent::Test::CommandHandlerHelpers` in your rspec config.
{: .notice--success}

You can then test your CommandHandlers via the stanza:

```ruby
it 'creates a user` do
  given_command CreateUser.new(args)
  then_events UserCreated
end
```


## Projector

Projectors are responsible for creating projections based on events. Projections are records in tables.
Sequent uses `ActiveRecord` for CRUD-ing records in the database. Sequent uses the term `Records` to
describe the Projections. In Sequent Projectors inherit from `Sequent::Projector`. To store something
in a Projection you need 3 things in `Sequent`:

1. A Projector
    Responsible for creating Projections. We are discussing Projectors in this chapter.
2. Record class
    This is a normal `ActiveRecord::Base` class. In Sequent Records can **only be updated/created/deleted
    inside Projectors**. The rest of the application needs to regard these objects as **read-only**.
    This however is **not enforced** in Sequent.
3. A SQL file describing the table in which the Record will be stored
    The nature of view state in event sourced applications is not compatible with `ActiveRecord` migration
    model. Therefor we don't use it. In event sourced applications the view state is **always** derived
    from Events. So when you want to have another view state, (maybe you add a column, or group some attributes)
    you replay the affected Projectors. Please checkout the chapter on [Migrations](#migrations)
    for an in-depth description on how migrations work in Sequent.

You define a Projector as follows:
```ruby
class UserProjector < Sequent::Projector
  manages_tables UserRecord
end
```

`Sequent::Projector` exposes the `manages_tables` method in which you state which
Records this Projector manages. There are two important things you need to know:

1. A Record can only be managed by one Projector.
  A Projector can however manage multiple Records.
2. A Projector can only access Records it manages.

A Projector is used in two different stages in your application.

1. During normal operation. This is when your application is running an Events are
  coming in. The Projector updates as you specified.
2. During migrations. During a migration some Projectors are rebuild in
  the background to build up new projections. Because of this a Projector
  can only access Record it manages, since the other Projector might not
  be finished yet rebuilding. In Sequent we replay on a **per aggregate**
  basis.

To use Projectors in your project you need to add them to the Sequent configuration

```ruby
  Sequent.configure do |config|
    config.event_handlers = [
      UserProjector.new
    ]
  end
```

### Creating a Record

```ruby
class UserProjector < Sequent::Projector
  on UserCreated do |event|
    create_record(UserRecord, {aggregate_id: event.aggregate_id})
  end
end
```

Internally a Projector uses a `Sequent::Core::Persistors::Persistor` to access the database.
During normal operations this is the `ActiveRecordPersistor`. This means the above code
is eventually translated to:

```ruby
user_record = UserRecord.new(aggregate_id: event.aggregate_id)
user_record.save!
```

`Sequent::Projector` provides a set of methods to create/read/update/delete Records as wrapper
around `ActiveRecord`. Reason for the extra abstraction is performance during migration of Projectors.
During a [migration](#migrations) a highly optimized Persistor, the `ReplayOptimizedPostgresPersistor`
is used to speed up bulk inserting.
Because of the abstraction you need to use the provided wrapper methods.
This poses some restrictions on how you can use `ActiveRecord` functionality.
For instance you can not add `child` relations via the parent as you might use to do in `ActiveRecord`.

```ruby
parent = ParentRecord.new
parent << ChildRecord.new
parent.save!
```

In Sequent this will **not work**. You need to persist child records the same
as you would persist the parent record.

```ruby
class UserProjector < Sequent::Projector
  on ParentCreated do |event|
    create_record(ParentRecord, {aggregate_id: event.aggregate_id})
    event.children.each do |child|
      create_record(ChildRecord, {parent_record_id: event.aggregate_id, child_id: child.child_id})
    end
  end
end
```


### Updating a record

You update a Record using the `update_all_records` passing in:

 - the Record
 - the where clause as a `Hash`
 - the updates as a `Hash`

```ruby
class UserProjector < Sequent::Projector
  on UserNameSet do |event|
    update_all_records(
      UserRecord,
      event.attributes.slice(:aggregate_id), # the where clause as a hash
      event.attributes.slice(:firstname, :lastname) # the updates as a hash
    )
  end
end
```

**Tip**:You can access all `attrs` from an Event via the `attributes` method. This returns a `Hash` on
which you can call `slice` which returns a `Hash` containing the key value pairs of the
keys you requested. This is extra handy of the name in the `attrs` are the same as the column
names in your table definition.
{: .notice--success}

### Deleting a record

Deleting a Record is pretty straight forward. Call the `delete_all_records`
with the Record and where clause.

```ruby
class UserProjector < Sequent::Projector
  on UserDeleted do |event|
    delete_all_records(
      UserRecord,
      event.attributes.slice(:aggregate_id), # the where clause as a hash
    )
  end
end
```

### Reading a record

You can also read a Records in a Projector. This is not very common but handy form time to time.
For instance you could a search column for each record for easy searching.

```ruby
class UserProjector < Sequent::Projector
  on UserNameSet do |event|
    user_record = get_record!(UserRecord, event.attributes.slice(:aggregate_id)
    search_field = "#{user_record.search_field} #{event.firstname} #{event.lastname}"

    update_all_records(
      UserRecord,
      event.attributes.slice(:aggregate_id), # the where clause as a hash
      event.attributes.slice(:firstname, :lastname).merge(search_field: search_field) # the updates as a hash
    )
  end
end
```

## Workflow

Workflows can be used to do other stuff based on [Events](#event) then updating a Projection. Typical
tasks run by Workflows are:

1) Execute other [Commands](#command)
2) Schedule something to run in the background

In Sequent Workflows are committed in the same transaction as committing the Events.

Since Workflows have nothing to do with Projections they do **not** run when doing a [Migration](#migrations).

To use Workflows in your project you need to add them to the Sequent configuration

```ruby
Sequent.configure do |config|
  config.event_handlers = [
    SendEmailWorkflow.new,
  ]
end
```

A Workflow responds to Event basically the same as Projectors do. For instance a Workflow
that will schedule a background Job using [DelayedJob](https://github.com/collectiveidea/delayed_job)
can look like this:

```ruby
class SendEmailWorkflow < Sequent::Workflow
  on UserCreated do |event|
    Delayed::Job.enqueue(event)
  end
end


class UserJob
  def initialize(event)
    @event = event
  end

  def perform
    ExternalService.send_email_to_user('Welcome User!', event.user_email_address)
  end
end
```


## AggregateRepository

The AggregateRepository is the interface for accessing Aggregates in the EventStore.

It is typically used in [CommandHandlers](#commandhandler) to load and add [AggregateRoots](#aggregateroot).

You can access the AggregateRepository via `Sequent.aggregate_repository`

## CommandService

The CommandService is the interface to schedule commands in Sequent. To execute a [Command](#command)
pass it to the CommandService. For instance from a Sinatra controller:

```ruby
class Users < Sinatra::Base
  post '/create' do
    Sequent.command_service.execute_commands CreateUser.new(
      aggregate_id: Sequent.new_uuid,
      name: params[:name]
    )
  end
end
```

## ValueObject

ValueObjects are convenience objects that can be used to group certain attributes that
are always used together in for instance commands. ValueObjects can be nested.
A ValueObject must inherit from `Sequent::Core::ValueObject`.

An example of a ValueObject is for instance an address.

```ruby
class Address < Sequent::Core::ValueObject
  attrs line_1: String, line_2: String, city: String, country_code: String
  validates_presence_of: :line_1, :city, :country_code
end
```

## Types

In Sequent events are stored as JSON in the event store. To be able to serialize and deserialize to the correct
types you are required to specify the type of an attribute.

This also gives Sequent the possibility to check if the attributes
in for instance the [Commands](#command) and [ValueObject](#valueobject) are of the correct type.

Out of the box Sequent supports the following types:

1. String: `attrs name: String`
2. Integer: `attrs counter: Integer`
3. Date: `attrs created_at: Date`
4. DateTime: `attrs created_at: DateTime`
5. Boolean: `attrs confirmed: Boolean`
6. Symbol: `attrs user_type: Symbol`
7. Custom ValueObjects: `attrs address: Address`
8. Lists: `attrs names: array(String)`

## Validations

Sequent uses [ActiveModel::Validations](http://api.rubyonrails.org/classes/ActiveModel/Validations.html)
for validating things like [Commands](#commands) and [ValueObjects](#valueobject).

For an in depth explanation of AvtiveModel validations please checkout their website.

Sequent already adds validations checking if the attribute is of the correct type
by default when you declare something an `Integer`, `Date`, `DateTime`, `Boolean` or as a custom `ValueObject`.

## Migrations

When you want to add or change Projections you need to migrate your view model.
The view model is **not** maintained via ActiveRecord's migrations. Reason for
this is that the ActiveRecord's model does not fit an event sourced application since the view model
is just an view on your events. This means we can just add or change new [Projectors](#projectors)
and rebuild the view model from the Events.

### How migrations work in Sequent.

To minize downtime in a Sequent application a migration is executed in two parts:

1. `bundle exec rake sequent::migrate::online`: Migrate while the application is running
2. `bundle exec rake sequent::migrate::offline`: Migrate last part when the application is down

#### Online migration

When creating new Projections Sequent is able to build up the new Projections
from [Events](#event) while the application is running. Sequent keeps track
of which Events are being replayed. The new Projections
are created in the view schema under unique names not visible
to the running app.

#### Offline migration

When the online migration part is done you need to run the offline migration part.
It is possible (highly likely) that new Events are being committed to the
event store during the migration online part. These new Events need to be
replayed by running `bundle exec rake sequent:migrate:offline`.

In order to ensure all events are replayed this part should only be run
after you put you application in maintenance mode and **ensure that no new Events are inserted in the event store**.
{: .notice--danger}

### Adding a migration

So a Migration in Sequent consists of:

1. Change or add Projectors
2. Change or add the corresponding sql files and its corresponding Records
3. Increase the version and add the Projectors that need to be rebuild in
the class configured in `Sequent.configuration.migrations_class_name`.

#### SQL files

A minimal SQL file looks like this:

```sql
CREATE TABLE account_records%SUFFIX% (
  id serial NOT NULL,
  aggregate_id uuid NOT NULL,
  CONSTRAINT account_records_pkey%SUFFIX% PRIMARY KEY (id)
);

CREATE UNIQUE INDEX unique_aggregate_id%SUFFIX% ON account_records%SUFFIX% USING btree (aggregate_id);
```

Please note that the usage of the **%SUFFIX%** placeholder. This needs to be added
to all names that are required to be unique in postgres. These are for instance:

- table names
- constraint names
- index names

The **%SUFFIX%** placeholder garantuees the uniqueness of names during the migration

#### Increase version number

In Sequent migrations are declared in your `Sequent.configuration.migrations_class_name`

```ruby
VIEW_SCHEMA_VERSION = 1

class Migrations < Sequent::Migrations::Projectors
  def self.version
    VIEW_SCHEMA_VERSION
  end

  def self.versions
    {
      '1' => [
        UserProjector,
      ]
    }
  end
end
```

To migrate add Projectors you need to rebuild and increase the version number:

You only need to add the Projectors to need to rebuild.

```ruby
VIEW_SCHEMA_VERSION = 2

class Migrations < Sequent::Migrations::Projectors
  def self.version
    VIEW_SCHEMA_VERSION
  end

  def self.versions
    {
      '1' => [
        UserProjector,
      ],
      '2' => [
        AccountProjector,
      ]
    }
  end
end
```
