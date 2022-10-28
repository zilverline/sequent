# Sequent

[![sequent Actions Status](https://github.com/zilverline/sequent/workflows/rspec/badge.svg)](https://github.com/zilverline/sequent/actions) [![Code Climate](https://codeclimate.com/github/zilverline/sequent/badges/gpa.svg)](https://codeclimate.com/github/zilverline/sequent) [![Test Coverage](https://codeclimate.com/github/zilverline/sequent/badges/coverage.svg)](https://codeclimate.com/github/zilverline/sequent)

> Sequent is a CQRS and event sourcing framework written in Ruby.

## Getting started

See the official site at https://www.sequent.io/

New to Sequent? [Getting Started](http://www.sequent.io/docs/getting-started.html) is the place to be!

## Contributing

Fork and send pull requests

## Documentation

See the official site at https://www.sequent.io/

Want to help improve the documentation? Please let us know how we can improve by [creating an issue](https://github.com/zilverline/sequent/issues/new)

If you want to help write the documentation fork and send pull request.

You can start the documentation locally via:

```
cd docs
bundle install
bundle exec jekyll serve --livereload
```

Open [localhost:4000](localhost:4000)

## Releasing

Change the version in `lib/version.rb`. Commit this change.

Then run `rake release`. A git tag will be created and pushed, and the new version of the gem will be pushed to rubygems.

## Running the specs

First create the database if you did not already do so:

```sh
createuser -D -s -R sequent
SEQUENT_ENV=test bundle exec rake sequent:db:create
```

Run `rspec spec` to run the tests.

## Changelog

The most notable changes can be found in the [Changelog](CHANGELOG.md)

## License

Sequent is released under the MIT License.
