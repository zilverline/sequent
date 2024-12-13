# frozen_string_literal: true

require_relative '../generator'
require_relative 'sequent_8_migration'
module Sequent
  module Cli
    class App
      extend GLI::App

      program_desc 'Sequent Command Line Interface (CLI)'

      version Sequent::VERSION
      on_error do |_error|
        true
      end

      desc 'Generate a directory structure for a Sequent project'
      command :new do |c|
        prompt = TTY::Prompt.new(interrupt: :exit)

        c.arg_name 'project_name'
        c.action do |_global, _options, args|
          help_now!('can only specify one single argument e.g. `sequent new project_name`') if args&.length != 1

          project_name = args[0]
          Sequent::Generator::Project.new(project_name).execute
          prompt.say(<<~EOS)
            Success!

            Your brand spanking new sequent app is waiting for you in:
              #{File.expand_path(project_name, Dir.pwd)}

            To finish setting up your app:
              cd #{project_name}
              bundle install
              bundle exec rake sequent:db:create
              bundle exec rake sequent:db:create_view_schema
              bundle exec rake sequent:migrate:online
              bundle exec rake sequent:migrate:offline

            Run the example specs:
              SEQUENT_ENV=test bundle exec rake sequent:db:create
              bundle exec rspec spec

            To generate new aggregates use:
              sequent generate <aggregate_name>. e.g. sequent generate address

            For more information see:
              https://www.sequent.io

            Happy coding!
          EOS
        rescue TargetAlreadyExists
          prompt.error("Target '#{project_name}' already exists, aborting")
        end
      end

      desc 'Generate a new aggregate, command, or event'
      command [:generate, :g] do |c|
        prompt = TTY::Prompt.new(interrupt: :exit)

        c.arg_name 'aggregate_name'
        c.desc 'Generate an aggregate'
        c.command :aggregate do |a|
          a.action do |_global, _options, args|
            if args&.length != 1
              help_now!('must specify one single argument e.g. `sequent generate aggregate Employee`')
            end

            aggregate_name = args[0]

            Sequent::Generator::Aggregate.new(aggregate_name).execute

            prompt.say(<<~EOS)
              #{aggregate_name} aggregate has been generated
            EOS
          end
        end

        c.desc 'Generate a command'
        c.arg_name 'aggregate_name command_name'
        c.command :command do |command|
          command.action do |_global, _options, args|
            if args&.length&.< 2
              help_now!('must specify at least two arguments e.g. `sequent generate command Employee CreateEmployee`')
            end

            aggregate_name, command_name, *attributes = args

            Sequent::Generator::Command.new(aggregate_name, command_name, attributes).execute
            prompt.say(<<~EOS)
              "#{command_name} command has been added to #{aggregate_name}"
            EOS
          rescue NoAggregateFound
            prompt.error("Aggregate '#{aggregate_name}' not found, aborting")
          end
        end

        c.desc 'Generate an Event'
        c.arg_name 'aggregate_name event_name'
        c.command :event do |command|
          command.action do |_global, _options, args|
            if args&.length&.< 2
              help_now!('must specify at least two arguments e.g. `sequent generate event Employee EmployeeCreated`')
            end

            aggregate_name, event_name, *attributes = args

            Sequent::Generator::Command.new(aggregate_name, event_name, attributes).execute
            prompt.say(<<~EOS)
              "#{event_name} event has been added to #{aggregate_name}"
            EOS
          rescue NoAggregateFound
            prompt.error("Aggregate '#{aggregate_name}' not found, aborting")
          end
        end
      end

      desc 'Migrates a Sequent 7 project to Sequent 8'
      command :migrate do |c|
        prompt = TTY::Prompt.new(interrupt: :exit)
        c.action do |_global, _options, _args|
          Sequent8Migration.new(prompt).execute
        rescue Gem::MissingSpecError
          prompt.error('Sequent gem not found. Please check your Gemfile.')
        rescue Sequent8Migration::Stop => e
          prompt.error(e.message)
        end
      end
    end
  end
end
