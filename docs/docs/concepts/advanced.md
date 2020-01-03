---
title: Advanced topics
---

CQRS and Event Sourcing are every powerful tools
and enable easy implementation for several complex requirements like: traceability, auditability and what-if scenario's. Sequent already provides out-of-the-box support for these concepts.

## Traceablity and auditability

When Commands are executed, Sequent already stores a reference
between the Commands and the resulting Events. Sequent also ensures
that Commands that are executed from Workflows will have a reference
to the causing Event.
By doing so Sequent provides a full audit trail for your event stream
by default.

You can query the audit trail as follows:

From a `Sequent::Core::CommandRecord`
```ruby
# From a CommandRecord
command_record = Sequent::Core::CommandRecord.find(1)

# The EventRecord that 'caused' this Command
command_record.parent

# Returns the top level Sequent::Core::CommandRecord that 'caused'
# this CommandRecord.
command_record.origin

# Returns the EventRecords caused by this command 
command_record.children
```

From a `Sequent::Core::EventRecord`
```ruby
event_record = Sequent::Core::EventRecord.find(1)

# Returns the Sequent::Core::CommandRecord that 'caused' this Event 
event_record.parent

# Returns the top level Sequent::Core::CommandRecord that 'caused'
# this Event. This traverses all the way up.
# When coming from Sequent < 3.2 this can also
# be an EventRecord. 
event_record.origin

# Returns the Sequent::Core::CommandRecord's that were execute because
# of this event 
event_record.children
```

## What if scenarios

Sometimes it can be useful to first check what will happen if a Command
is executed. Sequent provides a Dry Run option which you can use
in for instance rake tasks to check what will happen. Workflows and
Projectors are not actually executed nor are the Commands with
Events stored in the EventStore. This also implies that
the dry run will only be recorded "one level" deep: Only the fact
that a Workflow is executed will be recorded it does not execute
the actual registered `on` block.

**Important:** Dry run is **not Thread safe** since the Configuration
is changed and shared among Threads. So if you use this in a live
environment you will typically need invoke this from a stand-alone process
like a Rake task.
{: .notice--danger}


Example usage:

```ruby
result = Sequent.dry_run(send_invoice)

result.print(STDOUT)
```

This will for instance produce the following output:

```bash
+++++++++++++++++++++++++++++++++++
Command: SendInvoice resulted in 2 events
-- Event InvoiceSent was handled by:
-- Projectors: [InvoiceRecordProjector]
-- Workflows: []

-- Event InvoiceQueuedForEmail was handled by:
-- Projectors: [InvoiceRecordProjector]
-- Workflows: [EmailWorkflow]
+++++++++++++++++++++++++++++++++++
```
