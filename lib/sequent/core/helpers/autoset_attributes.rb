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
          def event_attribute_keys(event_class)
            event_class.types.keys.reject { |k| autoset_ignore_attributes.include?(k.to_s) }
          end

          def autoset_attributes_for_events(*event_classes)
            event_classes.each do |event_class|
              on event_class do |event|
                self.class.event_attribute_keys(event.class).each do |attribute_name|
                  instance_variable_set(:"@#{attribute_name}", event.public_send(attribute_name.to_sym))
                end
              end
            end
          end
        end

        def self.included(host_class)
          host_class.extend(ClassMethods)

          host_class.class_attribute :autoset_ignore_attributes,
                                     default: %w[aggregate_id sequence_number created_at],
                                     instance_reader: false,
                                     instance_writer: false

          # Deprecated
          host_class.singleton_class.alias_method :set_autoset_ignore_attributes, :autoset_ignore_attributes=
        end
      end
    end
  end
end
