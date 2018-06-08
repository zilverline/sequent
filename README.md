# Sequent

[![Build Status](https://travis-ci.org/zilverline/sequent.svg?branch=master)](https://travis-ci.org/zilverline/sequent) [![Code Climate](https://codeclimate.com/github/zilverline/sequent/badges/gpa.svg)](https://codeclimate.com/github/zilverline/sequent) [![Test Coverage](https://codeclimate.com/github/zilverline/sequent/badges/coverage.svg)](https://codeclimate.com/github/zilverline/sequent)

> Sequent is a CQRS and event sourcing framework written in Ruby.

## Getting started

See the official site at https://www.sequent.io/

New to Sequent? [http://localhost:4000/docs/getting-started.html](Getting started) is the place to be!

## Contributing

Fork and send pull requests

## Releasing

Change the version in `lib/version.rb`. Commit this change.

Then run `rake release`. A git tag will be created and pushed, and the new version of the gem will be pushed to rubygems.

## Running the specs

If you wish to make changes to the `sequent` gem you can use `rake spec` to run the tests. Before doing so you need to create a postgres
user and database first:

```sh
createuser -D -s -R sequent
createdb sequent_spec_db -O sequent
bundle exec rake db:create
```

The data in this database is deleted every time you run the specs!

## License

Sequent is released under the MIT License.
