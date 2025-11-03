---
title: Migrations
---

The projector migration process has changed significantly since Sequent 8. See [Migrations (Sequent
8)](/docs/concepts/migrations-sequent-8.html) for the previous, deprecated mechanism.
{: .notice--info}


When you want to add or change Projections you need to migrate your view model. Normal database
migrations (creating tables, adding columns, etc) can be done using ActiveRecord migrations.

Since the view tables are normally in a separate table you must use the
`Sequent::Support::Database.with_search_path` helper to manage tables in the correct schema. Below is
an example:

```ruby
class CreatePostRecords < ActiveRecord::Migration[8.0]
  def change
    Sequent::Support::Database.with_search_path(Sequent.configuration.view_schema_name) do
      create_table :post_records, id: :uuid, primary_key: :aggregate_id do |t|
        t.text :author
        t.text :title
        t.text :content
      end
    end
  end
end
```

Run the rake `db:migrate` or `sequent:db:migrate` commands to apply your changes to the schema
before replay.

Your existing application can keep running if your database migrations are back- and
forward-compatible!
{: .notice--info}


During normal operation the projectors run within the Sequent transaction to update
the view tables as events are committed. In other words, the view tables are fully consistent with
the event store.

However, when you add a new projector or update a projector to process events that were not
processed before you can *replay* the projector. This is done using the following steps:

```sh
$ bundle exec rake sequent:projectors:replay:prepare[AutherProjector,PostProjector]
```

This step creates a new schema (default `replay_schema`) and copies the *table definitions* of the
tables managed by the projectors from the view schema, including constraints. This is done using
`pg_dump` and `psql`, so these programs must be available. If you do not specify any projectors all
projectors will be included.

Note that the replay schema is *DROPPED* before creating the new tables
{: .notice--info}

Index definitions are not copied (except those needed to enforce constraints) as these slow down
database inserts during replay. If your projector relies on a particular index for data lookups you
can specify these using:

```ruby
class MyProjector < Sequent::Core::Projector
  # Can be a regexp or a list of index names and regexps
  self.additional_replay_indexes = %w[post_by_author_idx]
end
```

After the replay schema has been prepared the initial replay can be performed:

```sh
$ bundle exec rake sequent:projectors:replay:replay[100000,8]
```

The first parameter specifies how many events should be included in a single database transaction
(approximately) and the second parameter is the number of concurrent replay processes. If not
specified these parameters default to the Sequent configuration.

The initial replay uses an optimized persistence algorithm (keeping all records in memory and then
using a single database operation to insert every record) that can only be used when the replay
tables are still empty.

If the initial replay takes a long time and/or many new events are inserted by the running system
while the replay is taking place you can catchup to the most recent events incrementally using:

```sh
$ bundle exec rake sequent:projectors:replay:catchup[100000,8]
```

To complete the replay it is necessary to first prepare and optimize the tables, and build
additional indexes. This is done using:

```sh
$ bundle exec rake sequent:projectors:replay:optimize
```

Building indexes can take some time (and will also impact the running system). In additional, the
tables are [CLUSTER](https://www.postgresql.org/docs/current/sql-cluster.html)ed,
[VACUUM](https://www.postgresql.org/docs/current/sql-vacuum.html)ed, and
[ANALYZE](https://www.postgresql.org/docs/current/sql-analyze.html)d. This ensures the tables are
fully ready for use by the live system.

You are now ready to replace the existing tables in the view schema with the replayed tables. This
requires some locking and will stop the live system from updating projections, so it is important to
minimize the work done. It is *recommended* to run an incremental replay again before running:

```sh
$ bundle exec rake sequent:projectors:replay:golive
```

This step moves the existing view schema tables to the archive schema (default is `archive_schema`)
and moves the replayed tables to the view schema.

Note that the archive schema is *DROPPED* before moving the existing tables, so any old archived
data is lost!  {: .notice--danger}

Once the replayed tables are active in the view schema your code can now use the new projections.

## Handling errors

If the replay process fails at any point you can use:

```sh
$ bundle exec rake sequent:projectors:replay:abort
```

To abort the current replay process. The replay schema is dropped and all replayed data is
removed. You can then start again after fixing the problem that caused the replay failure.

If you need to know the status of the current replay process you can run:

```sh
$ bundle exec rake sequent:projectors:replay:status
```

for some additional information.
