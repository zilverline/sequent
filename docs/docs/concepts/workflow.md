---
title: Workflow
---

Workflows can be used to do other stuff (then updating a Projection) based on [Events](event.html). Common
tasks run by Workflows are:

1. Execute other [Commands](command.html)
2. Schedule something to run in the background

In Sequent Workflows are committed in the same transaction as committing the Events.

Since Workflows have nothing to do with Projections they do **not** run when doing a [Migration](migrations.html).

To use Workflows in your project you need to add them to your Sequent configuration:

```ruby
Sequent.configure do |config|
  config.event_handlers = [
    SendEmailWorkflow.new,
  ]
end
```

A Workflow responds to Event basically the same as Projectors do. For instance a Workflow
that will schedule a background Job using [DelayedJob](https://github.com/collectiveidea/delayed_job)
can look like this:

```ruby
class SendEmailWorkflow < Sequent::Workflow
  on UserCreated do |event|
    Delayed::Job.enqueue(event)
  end
end


class UserJob
  def initialize(event)
    @event = event
  end

  def perform
    ExternalService.send_email_to_user('Welcome User!', event.user_email_address)
  end
end
```

