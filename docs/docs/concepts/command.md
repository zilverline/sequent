---
title: Command
---

Commands form the API of your domain. Like [Events](event.html) they are simple data objects.
Commands have descriptive names describing the intent of what you are trying to achieve, for example `CreateUser` or `SendInvoice`.
Commands inherit from `Sequent::Command`. Additionally
you can add [Validations](validations.html) to commands to ensure correctness. Sequent uses
[ActiveModel::Validations](http://api.rubyonrails.org/classes/ActiveModel/Validations.html)
to enable validations.

```ruby
class CreateUser < Sequent::Command
  attrs firstname: String, lastname: String
  validates_presence_of :firstname, :lastname
end
```

Commands, like Events, are also stored in the [EventStore](event_store.html#command_records).

In building a web application you typically bind your html form to a Command. You then have to pass
it into the [CommandService](command-service.html). The CommandService will only execute valid Commands.
When a Command **is not valid** a `Sequent::Core::CommandNotValid` will be raised containing the validation `errors`.
When a Command **is valid** the [CommandHandlers](command-handler.html) registered and interested in this Command
will be invoked.
