---
title: Projector
---

Projectors are responsible for creating projections based on events. Projections are records in tables.
Sequent uses `ActiveRecord` for CRUD-ing records in the database. Sequent uses the term `Records` to
describe the Projections. In Sequent Projectors inherit from `Sequent::Projector`. To store something
in a Projection you need 3 things in `Sequent`:

1. A Projector. Responsible for creating Projections. We are discussing Projectors in this chapter.
2. A Record class. This is a `Sequent::ApplicationRecord` class, subclassing  `ActiveRecord::Base`. In Sequent Records can **only be updated/created/deleted
    inside Projectors**. The rest of the application needs to regard these objects as **read-only**.
    This however is **not enforced** in Sequent.
3. A SQL file. The SQL contains the table definition in which the Record will be stored. Please checkout the chapter
    on [Migrations](migrations.html)  for an in-depth description on how migrations work in Sequent.

The nature of view state in event sourced applications is not compatible with `ActiveRecord` migration
model. Therefor we don't use it. In event sourced applications the view state is **always derived**
from Events. So when you want to have another view state, (maybe you add a column, or group some attributes)
you replay the affected Projectors.
{: .notice--info}

In Sequent you define a Projector as follows:
```ruby
class UserProjector < Sequent::Projector
  manages_tables UserRecord
end
```

`Sequent::Projector` exposes the `manages_tables` method in which you state which
Records this Projector manages. There are two important things you need to know:

1. A Record can only be managed by one Projector.
  A Projector can however manage multiple Records.
2. A Projector should only access Records it manages.

A Projector is used in two different stages in your application.

1. During normal operation. This is when your application is running an Events are
  coming in. The Projector updates the Records as you specified.
2. During migrations. During a migration some Projectors are rebuild in
  the background to build up new projections. Because of this a Projector
  can only access Records it manages, since the other Projector might not
  be finished yet rebuilding. In Sequent we replay on a **per aggregate**
  basis.

To use Projectors in your project you need to add them to your Sequent configuration:

```ruby
  Sequent.configure do |config|
    config.event_handlers = [
      UserProjector.new
    ]
  end
```

## Creating a Record

To create a Record in Sequent you add a code block that listens to
the appropriate Event and creates a Record in the database.

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
During a [migration](migrations.html) a highly optimized Persistor, the `ReplayOptimizedPostgresPersistor`
is used to speed up bulk inserting.
Because of the abstraction you need to use the provided wrapper methods.
This poses some restrictions on how you can use `ActiveRecord` functionality.
For instance you can not add `child` relations via the parent as you might be used to do in a "normal" ActiveRecord application.

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


## Updating a record

To update a Record in Sequent use the `update_all_records` method. This method has 3 parameters:

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

**Tip**: You can access all `attrs` from an Event via the `attributes` method. This returns a `Hash` on
which you can call `slice` which returns a `Hash` containing the key value pairs of the
keys you requested. This is extra handy of the name in the `attrs` are the same as the column
names in your table definition.
{: .notice--success}

## Deleting a record

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

## Reading a record

You can also read a Records in a Projector. This is not very common but handy from time to time.
For instance you could update the search column for a record for easy searching.

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
