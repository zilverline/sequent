---
title: Event
---

An Event describes something that happened. They are named in passed tense. For instance `UserCreated`.
In Sequent Events are simple data objects with logical names describing what happened.
In Sequent Events subclass from `Sequent::Event`.
By subclassing from `Sequent::Event` you get 2 extra attributes: `aggregate_id` and `sequence_number`.
Both form the unique key of an Event.

An example of an Event in Sequent:

```ruby
class UserNameSet < Sequent::Event
  attrs name: String
end
```

To declare attributes you need to use the `attrs` keyword and provide it with a list of key value pairs
containing the name and [Type](types.html) of the attribute.

You can of course add multiple attributes to an Event

```ruby
class UserNameSet < Sequent::Event
  attrs firstname: String, lastname: String
end
```

You can also use `attrs` multiple times like

```ruby
class UserNameSet < Sequent::Event
  attrs firstname: String
  attrs lastname: String
end
```

The `attrs` will respect inheritance hierachies.

You can also use [ValueObject](value-object.html) in Events.

```ruby
class Name < Sequent::ValueObject
  attrs firstname: String, lastname: String
end

class UserNameSet < Sequent::Event
  attrs name: Name
end
```

Out of the box Sequent provides a whole set of [Types](types.html) you can use
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
