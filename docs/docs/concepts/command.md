---
title: Command
---

Commands form the API of your domain. They are simple data objects
with descriptive names describing the intent of your command. E.g. `CreateUser` or `SendInvoice`.
Commands inherit from `Sequent::Command`. Like [Events](event.html) they can be seen as structs. Additionally
you can add [Validations](validations.html) to commands to ensure correctness. Sequent uses
[ActiveModel::Validations](http://api.rubyonrails.org/classes/ActiveModel/Validations.html)
to enable validations.

```ruby
class CreateUser < Sequent::Command
  attrs firstname: String, lastname: String
  validates_presence_of :firstname, :lastname
end
```

In building a web application you typically bind your html form to a Command. It will
then be passed into the [CommandService](command-service.html) and Sequent takes care of the rest.
When a Command is not valid a `Sequent::Core::CommandNotValid` will be raised containing the validation `errors`.

