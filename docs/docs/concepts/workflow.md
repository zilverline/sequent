---
title: Workflow
---

Workflows can be used to do other stuff (than updating a Projection) based on [Events](event.html). Common
tasks run by Workflows are:

1. Execute other [Commands](command.html)
2. Schedule something to run in the background

In Sequent, Workflows are committed in the same transaction as committing the Events.

Since Workflows have nothing to do with Projections they do **not** run when doing a [Migration](migrations.html).

To use Workflows in your project you need to add them to your Sequent configuration:

```ruby
Sequent.configure do |config|
  config.event_handlers = [
    SendEmailWorkflow.new,
  ]
end
```

A Workflow responds to Events basically the same way as Projectors do. For instance a Workflow
that will schedule a background Job using [DelayedJob](https://github.com/collectiveidea/delayed_job)
can look like this:

```ruby
class SendEmailWorkflow < Sequent::Workflow
  on UserCreated do |event|
    Delayed::Job.enqueue UserJob.new(event)
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

If your Workflow has some side effects that can't be rolled back easily or if your background jobs processor
is not using the same database connection used for the transaction, you can wrap it in an `after_commit` block:

```ruby
class SendEmailWorkflow < Sequent::Workflow
  on UserCreated do |event|
    after_commit do
      SendEmailJob.perform_async(event)
    end
  end
end

class SendEmailJob
  include Sidekiq::Worker

  def perform(event)
    ExternalService.send_email_to_user('Welcome User!', event.user_email_address)
  end
end
```

It will run only and only if the transaction commits. Note that if you execute another command, it will be ran
synchronously but in a separate transaction. It will not be able to rollback the first one, resulting in some
Events to be commited and some other not. Only use `after_commit` if it is the intended behaviour.

**Handling Exceptions**: If an exception within an `after_commit` is not handled by the worker, it will stop
calling the other registered hooks. Make sure that you **rescue exceptions** and handle them properly. If you can
afford to ignore the errors and want to make sure all hooks are called, you can pass `ignore_errors: true` as a parameter.
{: .notice--warning}
