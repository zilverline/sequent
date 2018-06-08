require 'fileutils'
require 'active_support'
require 'active_support/core_ext/string'
require 'erb'
require 'parser/current'

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
        ast = Parser::CurrentRuby.parse(File.read("#{path_to_dir}/#{name_underscored}_command_handler.rb"))
        target_cursor_position = find_target_cursor_position(ast)
        
        File.open("#{path_to_dir}/#{name_underscored}_command_handler.rb", 'r+') do |f|
          f.seek(target_cursor_position, IO::SEEK_SET)
          lines_to_be_overwritten = f.read
          f.seek(target_cursor_position, IO::SEEK_SET)
          f << command_handler_template.result(binding).gsub(/^.+(\s)$/) { |x| x.gsub!($1, '')}
          f << lines_to_be_overwritten
        end
      end

      def find_target_cursor_position(ast)
        return unless ast.children.any?

        ast.children.reverse.map do |child|
          return if child.class.to_s != "Parser::AST::Node"
          return child.loc.expression.end_pos if child.type.to_s == 'block'
          find_target_cursor_position(child)
        end.flatten.compact.max
      end

      def append_command
        File.open("#{path_to_dir}/commands.rb", "a") { |f| f << command_template.result(binding) }
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

      def command_template
        ERB.new <<~EOF

          class <%= command %> < Sequent::Command
            <% attrs.each do |name, type| %>attrs <%= name.downcase %>: <%= type.downcase.capitalize %><% end %>
          end
        EOF
      end

      def command_handler_template
        ERB.new <<~EOF
          \n
            on <%= command %> do |command|

            end
        EOF
      end
    end
  end
end
