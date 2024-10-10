---
title: Types
---

In Sequent, events are stored as JSON in the event store. To be able to serialize and deserialize to the correct
types, you are required to specify the type of an attribute.

This also gives Sequent the ability to check that the attributes
in, for instance, [Command](command.html)s and [ValueObject](value-object.html)s are of the correct type.

Before a Command is executed, the [CommandService](command-service.html) ensures
that the attributes are validated and parsed to the correct types if necessary.

Out of the box Sequent supports the following types:

1. [String](#string)
1. [Integer](#integer)
1. [Date](#date)
1. [DateTime](#datetime)
1. [Time](#time)
1. [Boolean](#boolean)
1. [Symbol](#symbol)
1. [ValueObject](#valueobject)
1. [List](#list)
1. [Sequent::Secret](#sequentsecret)
1. [BigDecimal](#bigdecimal)


### String

Usage: `attrs name: String`

Valid strings are `nil` and anything that can be `to_s`-ed.
There are some invalid characters like `"\0000"` that Postgres can't handle.

When a String is considered invalid, the error code `invalid_string` is
added to the attribute in the ActiveModel `Errors` object during [validation](validations.html).

### Integer

Usage `attrs counter: Integer`

Registers the following Validation:

```
validates_numericality_of :counter, only_integer: true, allow_nil: true, allow_blank: true
```

To accommodate user input, Integers passed as Strings
are parsed automatically when a Command is passed to the CommandService.

### Date:

Usage `attrs created_at: Date`

Accepts all `Date` objects. To accommodate user input, valid
[ISO 8601](https://www.iso.org/iso-8601-date-and-time-format.html){:target="_blank"} date Strings are parsed automatically when
a Command is passed to the [CommandService](command-service.html).

## DateTime

**DEPRECATED** Use `Time` instead

Usage `attrs created_at: DateTime`

Accepts all `DateTime` objects. To accommodate user input, valid
[ISO 8601](https://www.iso.org/iso-8601-date-and-time-format.html){:target="_blank"} datetime Strings are parsed automatically when
a Command is passed to the CommandService.

## Time

Usage `attrs created_at: Time`

Accepts all `Time` objects. To accommodate user input, valid
[ISO 8601](https://www.iso.org/iso-8601-date-and-time-format.html){:target="_blank"} datetime Strings are parsed automatically when
a Command is passed to the CommandService.

## Boolean:

Usage `attrs confirmed: Boolean`

Valid Booleans are `true` `false` and `nil`. To accommodate user input
the values `"true"` and `"false"` are parsed to `true` and `false`
automatically when a Command is passed to the CommandService.

## Symbol:

Usage `attrs user_type: Symbol`

## ValueObject

Usage:

```ruby
class Money < Sequent::ValueObject
  attrs cents: Integer, currency: String
end

class MyEvent < Sequent::Event
  attrs amount: Money
end
```

Custom [ValueObjects](value-object.html) can contain other ValueObjects
with `attrs` of the Types described here.

## List

Usage: `attrs names: array(String)`

Lists can be a List of any Type described here.

## Sequent::Secret

Usage: `attrs password: Sequent::Secret`

This is a special type designed to work with user input (HTML forms).

It will irreversibly hash the attribute that is of type `Sequent::Secret` using bcrypt.

Usage:

```ruby
class CreateUser < Sequent::Command
  validates_presence_of :email, :password

  attrs email: String, password: Sequent::Secret
end

post '/create' do
  create_user = CreateUser.new(
    aggregate_id: Sequent.new_uuid,
    email: params[:email],
    password: params[:password],
  )

  Sequent.command_service.execute_commands create_user
end

class UserCommandHandler < Sequent::CommandHandler
  on CreateUser do |command|
    # 1. password is now of type Sequent::Secret
    # 2. the password is encrypted

  end
end
```

**There is no need to use this in Events since those should always contain the hashed secret.**
Events can store these values in plain Strings.

## BigDecimal

Usage: `attrs amount: BigDecimal`

Ruby's BigDecimal. **No special validations are added by default.** The value is passed to `BigDecimal.new(value)` as is.
