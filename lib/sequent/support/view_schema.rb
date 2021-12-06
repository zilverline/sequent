# frozen_string_literal: true

module Sequent
  module Support
    class ViewSchema < ActiveRecord::Schema
      def define(info, &block)
        view_projection = info[:view_projection]
        switch_to_schema(view_projection) if view_projection
        super
      ensure
        switch_back_to_original_schema if view_projection
      end

      def switch_to_schema(view_projection)
        @original_schema_search_path = connection.schema_search_path
        connection.schema_search_path = view_projection.schema_name
      end

      def switch_back_to_original_schema
        connection.schema_search_path = @original_schema_search_path
      end
    end
  end
end
