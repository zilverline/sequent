require_relative '../my_app'

Sequent::Support::ViewSchema.define(view_projection: MyApp::VIEW_PROJECTION) do
  create_table :account_records, :force => true do |t|
    t.string :aggregate_id, :null => false
    t.string :name
  end

  add_index :account_records, ["aggregate_id"], :name => "unique_aggregate_id_for_account", :unique => true
end
