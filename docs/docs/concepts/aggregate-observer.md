---
title: AggregateObserver
---

An `AggregateObserver` adds additional behavior to the domain that is triggered by [Events](event.html). Unlike a
[Workflow](workflow.html), an observer is invoked **immediately** as soon as the event is applied to the aggregate, and
observers can directly access other aggregates within the context of the current command.

Aggregate observers are mainly used to decouple aggregates without requiring the [CommandHandler](command-handler.html)
to explicitly orchestrate the interaction between them.

Since observers run within the domain and context of the currently executing command, they run inside the same
transaction as the command. If the observer raises an exception the entire command is rolled back.

## Registering an observer

If you did not set `enable_autoregistration` to `true` you need to add your observers manually to your Sequent
configuration:

```ruby
Sequent.configure do |config|
  config.aggregate_observers = [
    InvoiceObserver.new,
  ]
end
```

## Defining an observer

An `AggregateObserver` responds to Events in the same way as [Workflows](workflow.html) and
[Projectors](projector.html) do. For example, an observer that updates another aggregate whenever an invoice is sent
can look like this:

```ruby
class InvoiceObserver < Sequent::AggregateObserver
  on InvoiceSent do |event|
    sender = Sequent.aggregate_repository.load_aggregate(event.sender_id)
    sender.mark_sent_invoice(event.invoice_id)
  end
end
```

Because the observer is called while the originating command is still executing, any events it triggers (by loading
an aggregate and invoking a method that applies new events) are committed together with the events that triggered them.
