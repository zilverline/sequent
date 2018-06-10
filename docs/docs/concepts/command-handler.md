---
title: CommandHandler
---

CommandHandlers respond to certain [Commands](command.html). CommandHandlers inherit from `Sequent::CommandHandler`.
To respond to a certain [Command](command.html) a CommandHandler needs to register a block containing the action to be taken.

```ruby
class UserCommandHandler < Sequent::CommandHandler
  on CreateUser do |command|
    repository.add_aggregate(User.new(
      aggregate_id: command.aggregate_id,
      firstname: command.firstname,
      lastname: command.lastname,
    ))
  end
end
```


The `Sequent::CommandHandler` exposes two convenience methods:

1. `repository`, a shorthand for Sequent.configuration.aggregate_repository
2. `do_with_aggregate`, basically a shorthand for `respository.load_aggregate`

A CommandHandler can respond to multiple commands:

```ruby
class UserCommandHandler < Sequent::CommandHandler
  on CreateUser do |command|
    repository.add_aggregate(User.new(
      aggregate_id: command.aggregate_id,
      firstname: command.firstname,
      lastname: command.lastname,
    ))
  end

  on ApplyForLicense do |command|
    do_with_aggregate(command, User) do |user|
      user.apply_for_license
    end
  end
end
```

A CommandHandler can of course communicate with mulitple [AggregateRoots](aggregate-root.html).

```ruby
class UserCommandHandler < Sequent::CommandHandler
  on ApplyForLicense do |command|
    do_with_aggregate(command, User) do |user|
      license_server = repository.load_aggregate(command.license_server_id, LicenseServer)
      user.apply_for_license(license_server.generate_license_id)
    end
  end
end
```

To use CommandHandlers in your project you need to add them to your Sequent configuration.

```ruby
  Sequent.configure do |config|
    config.command_handlers = [
      UserCommandHandler.new
    ]
  end
```

### Testing your CommandHandlers

**Tip:** If you use rspec you can test your CommandHandler easily by including the `Sequent::Test::CommandHandlerHelpers` in your rspec config.
{: .notice--success}

You can then test your CommandHandlers via the stanza:

```ruby
it 'creates a user` do
  given_command CreateUser.new(args)
  then_events UserCreated
end
```
