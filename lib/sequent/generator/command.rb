require 'fileutils'
require 'active_support'
require 'active_support/core_ext/string'

class NoAggregateFound < StandardError; end

module Sequent
  module Generator
    class Command
      attr_reader :name, :command, :attrs

      def initialize(name, command, attrs)
        @name = name
        @command = command
        @attrs = attrs.map{|a| a.split(':')}
      end

      def execute
        ensure_existing_aggregate!
        add_command_to_aggregate
      end

      private

      def add_command_to_aggregate
        File.open("#{path_to_dir}/commands.rb", "a") do |f|
          f << "\n"
          if attrs.any?
            f << "class #{command} < Sequent::Command\n"
            attrs.each do |name, type|
              f << "  attrs #{name.downcase}: #{type.capitalize}\n"
            end
            f << "end"
          else
            f << "class #{command} < Sequent::Command; end"
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
        if !File.directory?(path_to_dir) || !File.exist?("#{path_to_dir}/#{name_underscored}_command_handler.rb") || !File.exist?("#{path_to_dir}/commands.rb")
          raise NoAggregateFound
        end
      end
    end
  end
end
