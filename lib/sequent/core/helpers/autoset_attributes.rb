# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      ##
      # In some cases you just want to store the events as instance variables
      # on the AggregateRoot. In that case you can use the following code:
      #
      # class LineItemsSet < Sequent::Event
      #   attrs line_items: array(LineItem)
      # end
      #
      # class Invoice < Sequent::AggregateRoot
      #   self.autoset_attributes_for_events LineItemsSet
      # end
      #
      # This will automatically create the following block
      #
      # on LineItemSet do |event|
      #   @line_items = event.line_items
      # end
      #
      # The +autoset_attributes_for_events+ will set all the defined +attrs+
      # as instance variable, except for the ones defined in +autoset_ignore_attributes+.
      #
      module AutosetAttributes
        module ClassMethods
          @@autoset_ignore_attributes = %w[aggregate_id sequence_number created_at]

          def set_autoset_ignore_attributes(attribute_names)
            @@autoset_ignore_attributes = attribute_names
          end

          def event_attribute_keys(event_class)
            event_class.types.keys.reject { |k| @@autoset_ignore_attributes.include?(k.to_s) }
          end

          def autoset_attributes_for_events(*args)
            args.each do |arg|
              on arg do |event|
                self.class.event_attribute_keys(event.class).each do |attribute_name|
                  instance_variable_set(:"@#{attribute_name}", event.public_send(attribute_name.to_sym))
                end
              end
            end
          end
        end

        def self.included(host_class)
          host_class.extend(ClassMethods)
        end
      end
    end
  end
end
