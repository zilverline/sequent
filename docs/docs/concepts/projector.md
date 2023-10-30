---
title: Projector
---

**Important**: Please take note for the current [known limitations](#known-limitations) when working with Projectors and Record classes.
{: .notice--warning}

Projectors are responsible for creating projections based on events. Projections are records in tables.
Sequent uses `ActiveRecord` for CRUD-ing records in the database. Sequent uses the term `Records` to
describe the Projections. In Sequent, Projectors inherit from `Sequent::Projector`. To store something
in a Projection you need 3 things in `Sequent`:

1. A Projector. Responsible for creating Projections. We are discussing Projectors in this chapter.
2. A Record class. This is a `Sequent::ApplicationRecord` class, subclassing `ActiveRecord::Base`. In Sequent, Records can **only be updated/created/deleted
    inside Projectors**. The rest of the application needs to regard these objects as **read-only**.
    This however is **not enforced** in Sequent.
3. An SQL file. The SQL contains the table definition in which the Record will be stored. Please check out the chapter
    on [Migrations](migrations.html) for an in-depth description on how migrations work in Sequent.

The nature of view state in event sourced applications is not compatible with the `ActiveRecord` migration
model, therefore it is not used. In event sourced applications the view state is **always derived**
from Events. When you want to have another view state (maybe you add a column, or group some attributes), 
you replay the affected Projectors.
{: .notice--info}

In Sequent a Projector is defined as follows:
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

1. During normal operation. This is when your application is running and Events are
  coming in. The Projector updates the Records as you specified.
2. During migrations. During a migration some Projectors are rebuilt in
  the background to build up new projections. Because of this, a Projector
  can only access Records it manages, since another Projector might not
  be finished rebuilding. In Sequent we replay on a **per aggregate**
  basis.

If you didn't set `enable_autoregistration` to `true` you will need to add your Projectors manually to your Sequent configuration in order to use them.

```ruby
  Sequent.configure do |config|
    config.event_handlers = [
      UserProjector.new
    ]
  end
```

## Creating a Record

To create a Record in Sequent, you add a code block that listens to
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
around `ActiveRecord`. The reason for the extra abstraction is performance during migration of Projectors.
During a [migration](migrations.html), a highly optimized Persistor - the `ReplayOptimizedPostgresPersistor` - 
is used to speed up bulk inserting.
Because of the abstraction, you need to use the provided wrapper methods.
This poses some restrictions on how you can use `ActiveRecord` functionality.
For instance you can not add `child` relations via the parent, as you might be used to in a "normal" ActiveRecord application.

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

To update a Record in Sequent, use the `update_all_records` method. This method has 3 parameters:

 - the Record class
 - the where clause as a `Hash` (generally using the `aggregate_id` attribute)
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
which you can call `slice`, which in turn returns a `Hash` containing the key value pairs of the
keys you requested. This is extra handy if the key names in the `attrs` are the same as the column
names in your table definition.
{: .notice--success}

## Deleting a record

To delete a Record in Sequent, use the `delete_all_records` method. This method has 2 parameters:

- the Record class
- the where clause as a `Hash` (generally using the `aggregate_id` attribute)

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

You can also read a Record in a Projector by using the `get_record` method. 
This method has 2 parameters:

- the Record class
- the where clause as a `Hash` (generally using the `aggregate_id` attribute)

It is not a very common use case, but handy from time to time.
For instance you could update the search column for a record for easy searching.

```ruby
class UserProjector < Sequent::Projector
  on UserNameSet do |event|
    user_record = get_record!(UserRecord, event.attributes.slice(:aggregate_id))
    search_field = "#{user_record.search_field} #{event.firstname} #{event.lastname}"

    update_all_records(
      UserRecord,
      event.attributes.slice(:aggregate_id), # the where clause as a hash
      event.attributes.slice(:firstname, :lastname).merge(search_field: search_field) # the updates as a hash
    )
  end
end
```

## Known limitations

1. You can not use `belongs_to` in your Record classes as these will fail if a parent relation does not exist. In a
normal application flow this is not a problem, only when replaying Projections this can become a problem due to the
order in which events are replayed. The only guarantee Sequent gives is that Events are replayed in order for a single
Aggregate, but there is no guaranteed order between different Aggregates.
2. For the same reason you can not use `belongs_to` you also can't use foreign key constraints in your view schema.
Relations between Aggregates are typically enforced in the Domain, so foreign key constraints are obsolete in the view schema.
For performance reasons you can of course still add indices on your foreign key columns.

