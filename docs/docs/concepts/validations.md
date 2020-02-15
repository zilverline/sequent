---
title: Validations
---

Sequent uses [ActiveModel::Validations](http://api.rubyonrails.org/classes/ActiveModel/Validations.html)
for validating things like [Commands](command.html) and [ValueObjects](value-object.html).

For an in depth explanation of all available ActiveModel validations please checkout the [Active Record Validations Guide](https://guides.rubyonrails.org/active_record_validations.html).

## Command validations

[Commands](command.html) are executed to get things done in Sequent. In a typical web application they are bound
to an HTML form. The `ActiveModel::Validations` can be used to validate the input values in the Command.

For example:

```html
<form action="/create" method="post">
  <input type="text" name="first_name">
  <input type="text" name="last_name">
  <button>Save</button>
</form>
```

```ruby
class CreateUser < Sequent::Command
  attrs first_name: String, last_name: String
  validates :first_name, presence: true, length: {minimum: 3, maximum: 100}
  validates :last_name, presence: true
end

post '/create' do
  Sequent.command_service.execute_commands(
    CreateUser.new(
      params.slice(:first_name, :last_name).merge(
        aggregate_id: Sequent.new_uuid
      )
    )
  )
end
```

The [CommandService](command-service.html) validates all Commands that are executed by calling `valid?`. If a Command is not valid
it raises a `Sequent::Core::CommandNotValid` error. The `Sequent::Core::CommandNotValid` has a reference to the Command which in
turn, since it is an ActiveModel object, has a reference to the `ActiveModel::Errors`. You can use this error to for instance
bind to your html form. Unfortunately, at the time of writing, the [Rails Form Helpers](https://guides.rubyonrails.org/form_helpers.html) only support ActiveRecord objects and not ActiveModel objects. So form binding should be done manually.

```ruby
post '/create' do
  Sequent.command_service.execute_commands(
    CreateUser.new(
      params.slice(:first_name, :last_name).merge(
        aggregate_id: Sequent.new_uuid
      )
    )
  )
  redirect '/list'
rescue Sequent::Core::CommandNotValid => e
  @command = e.command
  erb :new
end
```

You should handle the `Sequent::Core::CommandNotValid` since even if you validate you Command yourself in the
route before executed any registered synchronous [Workflow](workflow.html) executing Commands 
can also raise a `Sequent::Core::CommandNotValid`.

More [complex validations](#aggregate-root-validations) should be done in the [AggregateRoot](aggregate-root.html).

## Aggregate Root validations

Some validations can not be done in the Command since they are dependant on the current state of the `AggregateRoot`.
Sequent does not provide anything out of the box for this since it highly depends on your domain and is not
a Web framework trying to provide form binding.

Example:
```ruby
class QueueInvoiceForSending < Sequent::Command; end
class InvoiceAlreadyQueued < My::DomainError; end

class Invoice < Sequent::AggregateRoot
  def queue_for_sending
    fail InvoiceAlreadyQueued if @queued
    apply InvoiceQueuedForSending 
  end
  
  on InvoiceQueuedForSending do
    @queued = true
  end
end
```
In the above example the Command `QueueInvoiceForSending` has no validations. So executing it twice will have no effect
 on the validity of the Command. Only the AggregateRoot can know if this operation is allowed or not.

In for instance your web application you can then rescue from all `My::DomainError`s and show the user
an appropriate error message.
