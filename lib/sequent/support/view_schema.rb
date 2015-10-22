module Sequent
  module Support
    class ViewSchema < ActiveRecord::Schema
      def define(info, &block)
        view_schema = info[:view_schema]
        switch_to_schema(view_schema) if view_schema
        super
      ensure
        switch_back_to_original_schema if view_schema
      end

      def switch_to_schema(schema_info)
        schema = ViewProjection.new(schema_info)
        @original_schema_search_path = connection.schema_search_path
        connection.schema_search_path = schema.schema_name
      end

      def switch_back_to_original_schema
        connection.schema_search_path = @original_schema_search_path
      end
    end
  end
end
