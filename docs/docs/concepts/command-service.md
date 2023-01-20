---
title: CommandService
---

The CommandService is the interface to schedule commands in Sequent. To execute a [Command](command.html)
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


By default all Commands passed into the CommandService are executed in a single transaction.
When something fails and an Exception is raised and the transaction is rolled back.

## Order of Command execution

Commands are executed in the order in which they are scheduled. For instance
if you schedule new Commands in a [Workflow](workflow.html) running in the foreground
it will be added to the queue of Commands. For instance:

```ruby
# command c1 results in event e1
on c1 do
  apply e1
end

# workflow: event e1 results in new command c3
on e1 do
  execute_commands(c3)
end

# main
execute_commands(c1, c2)
```

The order in which Commands are "executed" is:

- `c1`
- `c2`
- `c3`

So Command `c1` results in [Event](event.html) `e1` that will result in
the execution of Command `c3`. However since Command `c2` is scheduled
first it will also be executed first.

## Order of Event publishing

Per Command the resulting Events are published and stored in the [EventStore](event_store.html). Events are published in order
in which the AggregateRoot is loaded from the [AggregateRepository](aggregate-repository.html).

Example:

```ruby

Sequent
  .command_service
  .execute_commands(MarkInvoicesPaid.new(...))

class InvoiceCommandHandler < Sequent::CommandHandler
  on MarkInvoicesPaid do
    invoice_1 = repository.load_aggregate(c1.aggregate_id)
    invoice_2 = repository.load_aggregate(c1.invoice_2_id)
    
    invoice_2.mark_paid # applies event InvoiceMarkPaid
    invoice_1.mark_paid # applies event InvoiceMarkPaid
    
    invoice_2.finalize # applies event InvoiceFinalized
    invoice_1.finalize # applies event InvoiceFinalized
  end
end
```
 
Given the above example the order in which the events are published is:

- `InvoiceMarkPaid` for `invoice_1`
- `InvoiceFinalized` for `invoice_1`
- `InvoiceMarkPaid` for `invoice_2`
- `InvoiceFinalized` for `invoice_2`

Since `invoice_1` is loaded first from the AggregateRepository all it's
Events (ordered as they occurred) as a result from the Command `MarkInvoicesPaid` will be published first. Then all events from `invoice_2` will be published.

## Middleware

You can add middleware to the CommandService. You can use this to execute code before and after a command is executed.
You can add multiple middlewares to the CommandService. The order in which they are executed is the order in which they are added.
Each middleware is executed once per execution of a command.

Each middleware needs to quack to `def call(command)`. For example:

```ruby
class LoggingCommandMiddleware
  def call(command)
    puts "Before executing command #{command}"

    yield # Don't forget to yield (this will call the next middleware in the chain (or execute the command when last in the chain)) 
  rescue StandardError => e
    puts "Error executing command #{command}"

    raise e
  ensure
    puts "After executing command #{command}"
  end
end

Sequent.configure do |config|
  config.command_middleware.add(LoggingCommandMiddleware.new)
end
```

When executing several commands:

```ruby
Sequent.configuration.command_service.execute_commands(
  CreateUser.new(
    aggregate_id: Sequent.new_uuid,
    name: 'John Doe'
  ),
  CreateUser.new(
    aggregate_id: Sequent.new_uuid,
    name: 'Jane Doe'
  )
)
```

Results into the following output:

```ruby
Before executing command #<CreateUser:0x00007fe933958d90 @aggregate_id="dc28438a-6f79-4353-b213-dbdd4e5e9876", @created_at=2023-01-19 14:42:19.541727 +0100, @name="John Doe">
After executing command #<CreateUser:0x00007fe933958d90 @aggregate_id="dc28438a-6f79-4353-b213-dbdd4e5e9876", @created_at=2023-01-19 14:42:19.541727 +0100, @name="John Doe">
Before executing command #<CreateUser:0x00007fe936a74be0 @aggregate_id="405327c9-a99e-49a6-ba21-7165db8af973", @created_at=2023-01-19 14:43:19.541947 +0100, @name="Jane Doe">
After executing command #<CreateUser:0x00007fe936a74be0 @aggregate_id="405327c9-a99e-49a6-ba21-7165db8af973", @created_at=2023-01-19 14:43:19.541947 +0100, @name="Jane Doe">
```