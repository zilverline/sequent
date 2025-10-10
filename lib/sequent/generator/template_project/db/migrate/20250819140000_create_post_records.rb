# frozen_string_literal: true

class CreatePostRecords < ActiveRecord::Migration[8.0]
  def change
    Sequent::Support::Database.with_search_path(Sequent.configuration.view_schema_name) do
      create_table :post_records, id: :uuid, primary_key: :aggregate_id do |t|
        t.text :author
        t.text :title
        t.text :content
      end
    end
  end
end
