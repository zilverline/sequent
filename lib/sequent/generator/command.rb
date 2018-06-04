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
      def append_command_handler
        File.open("#{path_to_dir}/#{name_underscored}_command_handler.rb", 'r+') do |file|
          lines = file.each_line.to_a
          target_index = lines.find_index("end\n")
          lines[target_index] = "\n"
          lines[target_index+1] = "  on #{command} do |command|\n"
          lines[target_index+2] = "  end\n"
          lines[target_index+3] = "end\n"
          file.rewind
          file.write(lines.join)
        end
      end

      def append_command
        File.open("#{path_to_dir}/commands.rb", "a") do |f|
          f << "\n"
          if attrs.any?
            f << "class #{command} < Sequent::Command\n"
            attrs.each do |name, type|
              f << "  attrs #{name.downcase}: #{type.downcase.capitalize}\n"
            end
            f << "end"
          else
            f << "class #{command} < Sequent::Command; end"
          end
          f << "\n"
        end
      end

      def add_command_to_aggregate
        append_command
        append_command_handler
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
