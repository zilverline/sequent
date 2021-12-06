# frozen_string_literal: true

require 'fileutils'
require 'active_support'
require 'active_support/core_ext/string'

class NoAggregateFound < StandardError; end

module Sequent
  module Generator
    class Event
      attr_reader :event, :attrs

      def initialize(name, event, attrs)
        @name = name
        @event = event
        @attrs = attrs.map { |a| a.split(':') }
      end

      def name
        @name ||= File.basename(path)
      end

      def execute
        ensure_existing_aggregate!
        add_event_to_aggregate
      end

      private

      def append_event
        File.open("#{path_to_dir}/events.rb", 'a') { |f| f << event_template.result(binding) }
      end

      def append_event_to_domain
        ast = Parser::CurrentRuby.parse(File.read("#{path_to_dir}/#{name_underscored}.rb"))
        target_cursor_position = find_target_cursor_position(ast)

        File.open("#{path_to_dir}/#{name_underscored}.rb", 'r+') do |f|
          f.seek(target_cursor_position, IO::SEEK_SET)
          lines_to_be_overwritten = f.read
          f.seek(target_cursor_position, IO::SEEK_SET)
          f << event_handler_template.result(binding).gsub(/^.+(\s)$/) { |x| x.gsub!(Regexp.last_match(1), '') }
          f << lines_to_be_overwritten
        end
      end

      def find_target_cursor_position(ast)
        return unless ast.children.any?
        return if ast.children.any? { |c| c.class.to_s != 'Parser::AST::Node' }
        if (child = ast.children.find { |c| c.type.to_s == 'block' })
          return child.loc.expression.end_pos
        end

        ast.children.reverse.map do |c|
          find_target_cursor_position(c)
        end.flatten.compact.max
      end

      def add_event_to_aggregate
        append_event
        append_event_to_domain
      end

      def path
        @path ||= File.expand_path('lib')
      end

      def name_underscored
        @name_underscored ||= name.underscore
      end

      def path_to_dir
        @path_to_dir ||= "#{path}/#{name_underscored}"
      end

      def ensure_existing_aggregate!
        fail NoAggregateFound if !File.directory?(path_to_dir) || !File.exist?("#{path_to_dir}/#{name_underscored}.rb")
      end

      def event_template
        ERB.new <<~EOF

          class <%= event %> < Sequent::Event
            <% attrs.each do |name, type| %>attrs <%= name.downcase %>: <%= type.downcase.capitalize %><% end %>
          end
        EOF
      end

      def event_handler_template
        ERB.new <<~EOF
          \n
            on <%= event %> do |event|

            end
        EOF
      end
    end
  end
end
