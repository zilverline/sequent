require 'fileutils'
require 'active_support'
require 'active_support/core_ext/string'

class NoAggregateFound < StandardError; end

module Sequent
  module Generator
    class Event
      attr_reader :name, :event, :attrs

      def initialize(name, event, attrs)
        @name = name
        @event = event
        @attrs = attrs.map{|a| a.split(':')}
      end

      def execute
        ensure_existing_aggregate!
        add_event_to_aggregate
      end

      private

      def add_event_to_aggregate
        File.open("#{path_to_dir}/events.rb", "a") do |f|
          f << "\n"
          if attrs.any?
            f << "class #{event} < Sequent::Event\n"
            attrs.each do |name, type|
              f << "  attrs #{name.downcase}: #{type.capitalize}\n"
            end
            f << "end"
          else
            f << "class #{event} < Sequent::Event; end"
          end
          f << "\n"
        end
      end

      def path
        @path ||= File.expand_path("lib")
      end

      def name
        @name ||= File.basename(path)
      end

      def name_underscored
        @name_underscored ||= name.underscore
      end

      def path_to_dir
        @path_to_dir ||= "#{path}/#{name_underscored}"
      end

      def ensure_existing_aggregate!
        if !File.directory?(path_to_dir) || !File.exist?("#{path_to_dir}/#{name_underscored}.rb")
          raise NoAggregateFound
        end
      end
    end
  end
end
