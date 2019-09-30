---
title: Migrations
---

When you want to add or change Projections you need to migrate your view model.
The view model is **not** maintained via ActiveRecord's migrations. Reason for
this is that the ActiveRecord's model does not fit an event sourced application.
Since the view model is a view on your events, you can add or change new [Projectors](projector.html) and rebuild the view model from the Events.

## How migrations work in Sequent.

Sequent supports 2 types of migrations:

### 1. ReplayTable

A ReplayTable will build up a table from [Events](event.html) from scratch. This is the
most commonly used migration.

### 2. AlterTable

This migration is an optimization migration and may come in handy for large projections.
Overtime your projections will grow. As you introduce new Events and want to use
this data in your projection you typically need to alter the table and add a column.
Since in this case the column will initially be empty (the Event does not yet exist) a
ReplayTable will work but is a bit overkill. For this reason you can also
specify an `alter_table` migration in which you can alter an existing table
and add a column.

## Defining migrations

In Sequent migrations are defined in your `Sequent.configuration.migrations_class_name`

### ReplayTable

To replay (existing or new) tables from scratch you can just specify
which Projectors you want to replay:

```ruby
VIEW_SCHEMA_VERSION = 1

class Migrations < Sequent::Migrations::Projectors
  def self.version
    VIEW_SCHEMA_VERSION
  end

  def self.versions
    {
      '1' => [
        UserProjector,
      ],
    }
  end
end
```

For clarity also a slimmed down version of the Projector and the Record:

```ruby
class UserRecord < Sequent::ApplicationRecord; end

class UserProjector
  manages_tables UserRecord
  # rest of code omitted for clarity
end
```

To be able to create the `UserRecord` Sequent expects a SQL file name
`user_records.sql` in the location `Sequent.configuration.migration_sql_files_directory`.
This location can be configured in Sequent's [Configuration](configuration.html).

```sql
CREATE TABLE user_records%SUFFIX% (
  id serial NOT NULL,
  aggregate_id uuid NOT NULL,
  CONSTRAINT user_records_pkey%SUFFIX% PRIMARY KEY (id)
);

CREATE UNIQUE INDEX unique_aggregate_id%SUFFIX% ON user_records%SUFFIX% USING btree (aggregate_id);
```

Please note that the usage of the **%SUFFIX%** placeholder. This needs to be added
to all names that are required to be unique in postgres. These are for instance:

- table names
- constraint names
- index names

The **%SUFFIX%** placeholder guarantees the uniqueness of names during the migration.

**Tip**: If you want to replay all projectors you can say `Sequent::Migrations.all_projectors`
instead of specifying each `Projector` individually.
{: .notice--success}

### AlterTable

When all you want to change an existing table **without replaying the events**
you can use:


```ruby
VIEW_SCHEMA_VERSION = 2

class Migrations < Sequent::Migrations::Projectors
  def self.version
    VIEW_SCHEMA_VERSION
  end

  def self.versions
    {
      '1' => [
        UserProjector,
      ],
      '2' => [
        Sequent::Migrations.alter_table(UserRecord),
      ],
    }
  end
end
```

To be able to run this migration Sequent expects, next to the `user_records.sql`,
a file called `user_records_2.sql` in the same location: `Sequent.configuration.migration_sql_files_directory`.
The contents of this file can be something like:

```sql
alter table user_records add column first_name character varying;
```

As you can see there is no need to use the **%SUFFIX%** placeholder in these migrations
since it is an in-place update.
{: .notice--info}

## Running migrations

Sequent provides some rake tasks to fully support a 3-phase-deploy to minimize downtime.
A typical scenario for upgrading your application:

Given that your application is deployed in directory `/app/version/1` and running
and you want to deploy a version `2` and need to migrate the view model

### 1. Install new version and run migrations
1. Install your application in `/app/version/2`
2. From within that directory run `bundle exec rake sequent:migrate:online`

When running this rake task Sequent is able to build up the new Projections
from [Events](event.html) while the application is running. Sequent keeps track
of which Events are being replayed. The new Projections
are created in the view schema under unique names, not visible
to the running app.
When the online migration part is done you need to run the [offline migration](#2-stop-application-and-finish-migrations) part.

### 2. Stop application and finish migrations
1. To ensure we get all events you now need to bring your application down and run
  `bundle exec rake sequent:migrate:offline`

It is possible (highly likely) that new Events are being committed to the
event store during the online migration part. These new Events need to be
replayed by running `bundle exec rake sequent:migrate:offline`.

In order to ensure all events are replayed this part should only be run
after you put you application in maintenance mode and **ensure that no new Events are inserted in the event store**.
{: .notice--danger}

To minimize downtime when replaying offline the event stream is scoped to the last 24 hours.
{: .notice--info}

**Pro-Tip**You can also choose to ensure no new Events are inserted by ensuring new Commands
are coming in. You can use [CommandFilters](configuration.html#commandfilters) to achieve this. This will minimize downtime event further.
{: .notice--info}

This is step in which the [AlterTable](#AlterTable) migrations are executed.

### Phase 3 - Switch to new version
6. If all went well you can now switch to `/app/version/2` and (re)start your application.

Congratulations! Your new version of your application is live.
