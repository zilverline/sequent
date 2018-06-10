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

The order in which Commands and Events are "executed" is:

- `c1`
- `c2`
- `c3`
- `e1`

