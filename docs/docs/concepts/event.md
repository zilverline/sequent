---
title: Event
---

An Event describes something that happened. They are named in past tense e.g. `UserCreated`.
In Sequent, Events are simple data objects with logical names describing what happened.
Events inherit from `Sequent::Event`, which adds 2 extra attributes: `aggregate_id` and `sequence_number`.
Both form the unique key of an Event. Events are stored in the [EventStore](event_store.html#event_records).

An example of an Event in Sequent:

```ruby
class UserNameSet < Sequent::Event
  attrs name: String
end
```

To declare attributes you need to use the `attrs` keyword and provide it with a list of key value pairs
containing the name and [Type](types.html) of the attribute.

It is possible to add multiple attributes to an Event:

```ruby
class UserNameSet < Sequent::Event
  attrs firstname: String, lastname: String
end
```

You can also use `attrs` multiple times:

```ruby
class UserNameSet < Sequent::Event
  attrs firstname: String
  attrs lastname: String
end
```

The `attrs` will respect inheritance hierarchies.

You can also use [ValueObject](value-object.html) in Events.

```ruby
class Name < Sequent::ValueObject
  attrs firstname: String, lastname: String
end

class UserNameSet < Sequent::Event
  attrs name: Name
end
```

Sequent provides a whole set of built-in [Types](types.html) you can use
for defining your attributes.

<div class="notice--info">
<strong>Recommendations:</strong>
  <ul>
    <li>Keep Events small.</li>
    <li>When an attribute changes, use the same event.
        This makes it easier to keep track of state changes in Projectors or Workflows.</li>
    <li>Keep events as flat as possible. Overly nested <code>ValueObject</code>s might seem to remove duplication, but is not always practical in usage.</li>
  </ul>
</div>


**Renaming Events**: When running in production and you decide to rename an Event, you **must** also
update all [EventRecords](event_store.html#event_records) for this Event's type.
{: .notice--warning}

**Renaming attributes in Events**: Since Events are stored as JSON in the EventStore, renaming
attributes in Events will break deserializing. If you want to change an attribute's name
anyway, you **must** also update all Events in your EventStore.
{: .notice--warning}
