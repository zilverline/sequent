---
title: Advanced topics
---

CQRS and Event Sourcing are very powerful tools
which enable easy implementation for several complex requirements like: traceability, auditability and what-if scenario's. Sequent already provides out-of-the-box support for these concepts.

## Traceability and auditability

When Commands are executed, Sequent already stores a reference
between the Commands and the resulting Events. Sequent also ensures
that Commands that are executed from Workflows will have a reference
to the causing Event.
By doing so, Sequent provides a full audit trail for your event stream
by default.

You can query the audit trail as follows:

From a `Sequent::Core::CommandRecord`
```ruby
# From a CommandRecord
command_record = Sequent::Core::CommandRecord.find(1)

# The EventRecord that 'caused' this Command
command_record.parent

# Returns the top level Sequent::Core::CommandRecord that 'caused'
# this CommandRecord.
command_record.origin

# Returns the EventRecords caused by this command
command_record.children
```

From a `Sequent::Core::EventRecord`
```ruby
event_record = Sequent::Core::EventRecord.find(1)

# Returns the Sequent::Core::CommandRecord that 'caused' this Event
event_record.parent

# Returns the top level Sequent::Core::CommandRecord that 'caused'
# this Event. This traverses all the way up.
# When coming from Sequent < 3.2 this can also
# be an EventRecord.
event_record.origin

# Returns the Sequent::Core::CommandRecord's that were execute because
# of this event
event_record.children
```

## Upcasting

When designing your domain (`AggregateRoot`s, `Event`s, `Command`s), over time you might want to change a particular `Event`. Perhaps you want to rename an attribute.
One strategy could be to just run an update query on your `EventRecord` and be done with it. If you are still
in the startup phase and really exploring the domain, this could certainly occur. It does however go
against the immutable nature of an EventStore.
In order to accommodate for refactorings like renaming - typically called *upcasting* in event sourcing - Sequent
allows you to register upcasters in `Event`s and `ValueObject`s as follows:

```ruby
# Initial version of the InvoiceSent event
class InvoiceSent < Sequent::Event
  attrs send_date: Date
end

# a few months into production, the term invoice_date better
# fits the domain you decide to refactor and rename the attribute

# The new InvoiceSent event
class InvoiceSent < Sequent::Event
  attrs invoice_date: Date

  upcast do |hash|
    hash['invoice_date'] = hash['send_date']
  end
end
```

Old events (persisted as version 1) will still contain `send_date` as an attribute in the `event_json`.
Later versions will persist the attribute as `invoice_date`. The old events will not be changed in the
event store.

You can define multiple upcasters. They run in the order in which they are defined:

```ruby
class InvoiceSet < Sequent::Event
  attrs invoice_date: Date, full_name: String

  upcast do |hash|
    hash['full_name'] = hash['fullname']
  end

  upcast do |hash|
    hash['invoice_date'] = hash['send_date']
  end
end
```

## What-if scenarios

Sometimes it can be useful to check what would happen if a Command
were to be executed, without actually executing it. Sequent provides a Dry Run option which you can use
in, for instance, rake tasks to check what will happen. Workflows and
Projectors are not actually executed, nor are the Commands with
Events stored in the EventStore. This also implies that
the dry run will only be recorded "one level" deep: Only the fact
that a Workflow is executed will be recorded; it does not execute
the actual registered `on` block.

**Important:** Dry run is **not Thread safe** since the Configuration
is changed and shared among Threads. If you use this in a live
environment you will typically need to invoke this from a stand-alone process
like a Rake task.
{: .notice--danger}


Example usage:

```ruby
result = Sequent.dry_run(send_invoice)

result.print(STDOUT)
```

This will, for instance, produce the following output:

```bash
+++++++++++++++++++++++++++++++++++
Command: SendInvoice resulted in 2 events
-- Event InvoiceSent was handled by:
-- Projectors: [InvoiceRecordProjector]
-- Workflows: []

-- Event InvoiceQueuedForEmail was handled by:
-- Projectors: [InvoiceRecordProjector]
-- Workflows: [EmailWorkflow]
+++++++++++++++++++++++++++++++++++
```

## Message matching

Since Sequent 5.0, each `Sequent::Core::Helpers::MessageHandler` (`Sequent::AggregateRoot`, `Sequent::Projector`, `Sequent::Workflow` and `Sequent::CommandHandler`) has support for declarative matching of messages.

This works as follows:

```ruby
module MyModule; end

class Money < Sequent::ValueObject
  attrs cents: Integer, currency: String
end

class MyEvent < Sequent::Event
  include MyModule

  attrs some_attribute: String,
        amount: Money
end

class MyExcludedEvent < Sequent::Event
  include MyModule
end

class MyWorkflow < Sequent::Workflow
  on MyEvent do |event|
    # you can keep matching on class name
  end

  on is_a(MyModule) do |event|
    # matches any event whose class includes MyModule
  end

  on is_a(MyModule, except: MyExcludedEvent) do |event|
    # matches any event whose class includes MyModule, but not MyExcludedEvent
  end

  on is_a(Sequent::Event) do |event|
    # matches any event whose super class is Sequent::Event
  end

  on any do |event|
    # matches any event
  end

  on any(except: MyExcludedEvent) do |event|
    # matches any event except MyExcludedEvent
  end

  on has_attrs(MyEvent, sequence_number: gt(100)) do |event|
    # matches events of class MyEvent with a sequence number greater than 100
  end

  on has_attrs(MyEvent, amount: {cents: gt(100), currency: neq('USD')}) do |event|
    # matches events of class MyEvent and have an amount of cents greater than 100 and a currency not equal to USD
  end

  on has_attrs(is_a(MyModule), some_attribute: eq('some value')) do |event|
    # matches events that include MyModule and have some_attribute with a value of 'some value'
  end

  on has_attrs(MyEvent, some_attribute: 'some value') do |event|
    # eq can also be omitted, since it's the default matcher of an attr value
  end
end
```

For a list of supported built-in message matchers, see: https://www.rubydoc.info/gems/sequent/Sequent/Core/Helpers/MessageMatchers.

For a list of supported built-in attr matchers, see: https://www.rubydoc.info/gems/sequent/Sequent/Core/Helpers/AttrMatchers.

### Custom message matcher

You can also provide your own custom message matchers as follows:

```ruby
MyMessageMatcher = Struct.new(:expected_argument) do
  def matches_message?(message)
    # return a truthy value if it matches, or falsey otherwise.
  end

  def to_s
    "my_message_matcher(#{Sequent::Core::Helpers::MessageMatchers::ArgumentSerializer.serialize_value(expected_value)})"
  end
end

Sequent::Core::Helpers::MessageMatchers.register_matcher :my_message_matcher, MyMessageMatcher
```

> Be sure to use `Struct` as a basis for your matcher, otherwise you have to manually do a proper 'equals'
implementation by overriding the `#==`, `#eql?` and `#hash` methods.

Your custom matcher can be used as follows (note that the first (`name`) argument provided to `register_matcher` becomes
the method name used in `on` (ie. `my_message_matcher`)):

```ruby
class MyWorkfow < Sequent::Workflow
  on my_message_matcher('some constraint') do |event|
    # ...
  end
end
```

### Custom attr matcher

You can also provide your own custom attr matchers as follows:

```ruby
MyAttrMatcher = Struct.new(:expected_value) do
  def matches_message?(actual_value)
    # return a truthy value if it matches, or falsey otherwise.
  end

  def to_s
    "my_attr_matcher(#{Sequent::Core::Helpers::AttrMatchers::ArgumentSerializer.serialize_value(expected_value)})"
  end
end

Sequent::Core::Helpers::AttrMatchers.register_matcher :my_attr_matcher, MyAttrMatcher
```

> Be sure to use `Struct` as a basis for your matcher, otherwise you have to manually do a proper 'equals'
implementation by overriding the `#==`, `#eql?` and `#hash` methods.

Your custom matcher can be used as follows (note that the first (`name`) argument provided to `register_matcher` becomes
the method name used in `on` (ie. `my_attr_matcher`)):

```ruby
class MyWorkfow < Sequent::Workflow
  on has_attrs(MyEvent, my_attribute: my_attr_matcher('expected value')) do |event|
    # ...
  end
end
```

## Message handler load-time options

Since Sequent 5.0, each `Sequent::Core::Helpers::MessageHandler` (`Sequent::AggregateRoot`, `Sequent::Projector`, `Sequent::Workflow` and `Sequent::CommandHandler`) has support for processing load-time options.

This works as follows:

```ruby
class MyBaseWorkflow < Sequent::Workflow
  option :deduplicate_on do |matchers, attributes|
    # This block is called for each defined `on` block that provides the corresponding option.
    #
    # In this example this is only once (for `on MyEvent, deduplicate_on: %i[aggregate_id]`, not for `on OtherEvent`).
    #
    # The first argument to this block is a list of message matchers (as defined in the `on` definition).
    # The second argument is the value specified as an argument to the option in the `on` definition.

    matchers == [Sequent::Core::Helpers::MessageMatchers::InstanceOf.new(MyEvent)] # true
    attributes == %i[aggregate_id] # true
  end
end

class MyWorkflow < MyBaseWorkflow
  on MyEvent, deduplicate_on: %i[aggregate_id] do |event|
    # ...
  end

  on OtherEvent do |event|
    # ...
  end
end
```

Registered options are scoped per class hierarchy, so in the above example, all workflows extending from `MyBaseWorkflow` support the `deduplicate_on` option in `on` definitions. Classes in other hierarchies (like a `Sequent::Projector`) will not have this option (but can register their own options of course).
