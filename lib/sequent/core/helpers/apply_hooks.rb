# frozen_string_literal: true

require 'active_support'
require 'active_support/core_ext/class/attribute'

require_relative 'message_matchers/message_matchers'

module Sequent
  module Core
    module Helpers
      ##
      # Hooks run code before, after or around each event an aggregate root applies, for example to
      # check a condition that must hold before and after every change:
      #
      #   class Invoice < Sequent::AggregateRoot
      #     before_apply(except: InvoiceCreated) { |event| fail 'invoice is sent' if @sent }
      #     after_apply :check_total, only: [LineAdded, LineAmountChanged]
      #
      #     # An around hook continues by calling the continuation, a method by yielding.
      #     around_apply { |event, continuation| Instrumenter.instrument(event.class.name) { continuation.call } }
      #     around_apply :guard_closed_period
      #
      #     def guard_closed_period(event)
      #       fail_if_closed!(period)
      #       yield
      #       fail_if_closed!(period)
      #     end
      #   end
      #
      # The hooks only run when an event is applied, not when the aggregate is loaded. The before hooks
      # run in the order in which they are declared, then the around hooks (the first declared hook is
      # the outermost), the event and the after hooks. +only+ and +except+ take the same arguments as
      # +on+: an event class matches that class exactly, use <tt>is_a(SomeEvent)</tt> to include its
      # subclasses. Other message matchers like +has_attrs+ work as well. When a hook raises, the event is
      # not added to the uncommitted events; an after hook runs once the event has changed the state. An
      # around hook must continue: not applying the event fails. Hooks are inherited by subclasses.
      #
      module ApplyHooks
        ApplyHook = Data.define(:kind, :callable, :only, :except) do
          def applies_to?(event)
            (only.nil? || only.any? { |matcher| matcher.matches_message?(event) }) &&
              (except.nil? || except.none? { |matcher| matcher.matches_message?(event) })
          end

          def call(host, event, &continuation)
            if callable.is_a?(Proc)
              args = kind == :around ? [event, continuation] : [event]
              host.instance_exec(*args, &callable)
            else
              host.__send__(callable, event, &continuation)
            end
          end
        end

        module ClassMethods
          def before_apply(method_name = nil, only: nil, except: nil, &block)
            add_apply_hook(:before, method_name, block, only, except)
          end

          def after_apply(method_name = nil, only: nil, except: nil, &block)
            add_apply_hook(:after, method_name, block, only, except)
          end

          def around_apply(method_name = nil, only: nil, except: nil, &block)
            add_apply_hook(:around, method_name, block, only, except)
          end

          private

          def add_apply_hook(kind, method_name, block, only, except)
            if method_name.nil? == block.nil?
              fail ArgumentError, "#{kind}_apply requires either a method name or a block"
            end
            fail ArgumentError, "#{kind}_apply takes either only or except" if only && except

            only, except = [only, except].map do |matchers|
              next if matchers.nil?

              matchers = [matchers] unless matchers.is_a?(Array)
              matchers.map { |matcher| MessageMatchers::ArgumentCoercer.coerce_argument(matcher) }.freeze
            end

            self.apply_hooks = [*apply_hooks, ApplyHook.new(kind, method_name || block, only, except)].freeze
          end
        end

        def self.included(host_class)
          host_class.extend(ClassMethods)

          host_class.class_attribute :apply_hooks,
                                     default: [].freeze,
                                     instance_reader: false,
                                     instance_writer: false
        end

        private

        def run_apply_hooks(event, &apply)
          hooks = self.class.apply_hooks.select { |hook| hook.applies_to?(event) }
          return yield if hooks.empty?

          applied = false
          hooks.each { |hook| hook.call(self, event) if hook.kind == :before }
          run_around_apply_hooks(hooks.select { |hook| hook.kind == :around }, event) do
            apply.call
            applied = true
          end
          fail "an around_apply hook of #{self} did not apply #{event.class}" unless applied

          hooks.each { |hook| hook.call(self, event) if hook.kind == :after }
        end

        def run_around_apply_hooks(hooks, event, &apply)
          return yield if hooks.empty?

          first, *rest = hooks
          first.call(self, event) { run_around_apply_hooks(rest, event, &apply) }
        end
      end
    end
  end
end
