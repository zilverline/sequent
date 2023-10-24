# frozen_string_literal: true

describe 'Sequent', type: :system do
  it 'correctly autoloads CommandHandlers and EventHandlers' do
    expect(Sequent.configuration.command_handlers.map(&:class).sort_by(&:name)).to eq [
      Invoicing::CommandHandler,
      Sequent::Core::AggregateSnapshotter,
    ]
    expect(Sequent.configuration.event_handlers.map(&:class).sort_by(&:name)).to eq [
      InvoiceWorkflow,
    ]
  end
end
