# Sequent

[![sequent Actions Status](https://github.com/zilverline/sequent/workflows/rspec/badge.svg)](https://github.com/zilverline/sequent/actions) [![Code Climate](https://codeclimate.com/github/zilverline/sequent/badges/gpa.svg)](https://codeclimate.com/github/zilverline/sequent) [![Test Coverage](https://codeclimate.com/github/zilverline/sequent/badges/coverage.svg)](https://codeclimate.com/github/zilverline/sequent)

> Sequent is a CQRS and event sourcing framework written in Ruby.

## Getting started

See the official site at https://www.sequent.io/

New to Sequent? [Getting Started](http://www.sequent.io/docs/getting-started.html) is the place to be!

## Contributing

Fork and send pull requests

## Documentation

See the official site at https://sequent.io/

Want to help improve the documentation? Please let us know how we can improve by [creating an issue](https://github.com/zilverline/sequent/issues/new)

If you want to help write the documentation fork and send pull request.

You can start the documentation locally via:

```
cd docs
bundle install
cp .env.example .env
bundle exec jekyll serve --livereload
```

Open [localhost:4000](http://localhost:4000)

A GitHub personal access token is required if you want Jekyll to retrieve GitHub metadata information.
[Create a new personal access token](https://github.com/settings/tokens/new) (no scope is required) and configure it in the .env file.

## Releasing

Ensure the version in `lib/version.rb` is the new version. If not change it and commit this change.

Then run `rake release`. A git tag will be created and pushed, and the new version of the gem will be pushed to rubygems.

Increase version to new working version, update the sequent version for all the `gemfiles`: 

```
BUNDLE_GEMFILE=gemfiles/ar_7_1.gemfile bundle update sequent --conservative
BUNDLE_GEMFILE=gemfiles/ar_7_2.gemfile bundle update sequent --conservative
```

## Running the specs

### Database setup
* When using a local PostgreSQL database, create the user:
  ```shell
  createuser -D -s -R sequent
  ```
* If you're not using a local Postgres database, setup the database using docker:
  ```shell
  docker run --name sequent -e POSTGRES_HOST_AUTH_METHOD=trust -e POSTGRES_USER=sequent -p 5432:5432 -d postgres:16
  ```

### Create the database
Have Sequent create the database:
```shell
SEQUENT_ENV=test bundle exec rake sequent:db:create
```

Run `rspec spec` to run the tests with the current database schema.

To ensure the specs use the latest database schema run:

```
SEQUENT_ENV=test rake sequent:db:drop sequent:db:create spec
```

## Changelog

The most notable changes can be found in the [Changelog](CHANGELOG.md)

## License

Sequent is released under the MIT License.
