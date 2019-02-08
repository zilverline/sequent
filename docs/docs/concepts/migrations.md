---
title: Migrations
---

When you want to add or change Projections you need to migrate your view model.
The view model is **not** maintained via ActiveRecord's migrations. Reason for
this is that the ActiveRecord's model does not fit an event sourced application since the view model
is just a view on your events. This means we can just add or change new [Projectors](projector.html)
and rebuild the view model from the Events.

## How migrations work in Sequent.

To minize downtime in a Sequent application a migration is executed in two parts:

1. `bundle exec rake sequent::migrate::online`: Migrate while the application is running
2. `bundle exec rake sequent::migrate::offline`: Migrate last part when the application is down

## Online migration

When creating new Projections Sequent is able to build up the new Projections
from [Events](event.html) while the application is running. Sequent keeps track
of which Events are being replayed. The new Projections
are created in the view schema under unique names, not visible
to the running app.

## Offline migration

When the online migration part is done you need to run the offline migration part.
It is possible (highly likely) that new Events are being committed to the
event store during the online migration part. These new Events need to be
replayed by running `bundle exec rake sequent:migrate:offline`.

In order to ensure all events are replayed this part should only be run
after you put you application in maintenance mode and **ensure that no new Events are inserted in the event store**.
{: .notice--danger}

To minimize downtime when replaying offline the event stream is scoped to the last 24 hours.
{: .notice--info}

## Adding a migration

So a Migration in Sequent consists of:

1. Change or add Projectors
2. Change or add the corresponding SQL files and its corresponding Records
3. Increase the version and add the Projectors that need to be rebuild in
the class configured in `Sequent.configuration.migrations_class_name`.

## SQL files

A minimal SQL file looks like this:

```sql
CREATE TABLE account_records%SUFFIX% (
  id serial NOT NULL,
  aggregate_id uuid NOT NULL,
  CONSTRAINT account_records_pkey%SUFFIX% PRIMARY KEY (id)
);

CREATE UNIQUE INDEX unique_aggregate_id%SUFFIX% ON account_records%SUFFIX% USING btree (aggregate_id);
```

Please note that the usage of the **%SUFFIX%** placeholder. This needs to be added
to all names that are required to be unique in postgres. These are for instance:

- table names
- constraint names
- index names

The **%SUFFIX%** placeholder garantuees the uniqueness of names during the migration.

## Increase version number

In Sequent migrations are declared in your `Sequent.configuration.migrations_class_name`

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
      ]
    }
  end
end
```

To migrate add Projectors you need to rebuild and increase the version number:

You only need to add the Projectors that need to be rebuild.

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
        AccountProjector,
      ]
    }
  end
end
```
