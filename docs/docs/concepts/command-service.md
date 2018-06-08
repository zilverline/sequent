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
