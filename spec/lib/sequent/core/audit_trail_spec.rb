# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core do
  let(:aggregate_id) { Sequent.new_uuid }

  class TestAuditCommand < Sequent::Core::Command; end
  class TestAuditEvent < Sequent::Core::Event; end
  class TestCausedByCommand < Sequent::Core::Command; end
  class TestCausedByEvent < Sequent::Core::Event; end

  let(:aggregate_id_1) { Sequent.new_uuid }
  let(:aggregate_id_2) { Sequent.new_uuid }

  it 'tracks cause-and-effect for commands and events' do
    audit_event = TestAuditEvent.new(
      aggregate_id: aggregate_id_1,
      sequence_number: 1,
      created_at: Time.parse('2024-02-29T09:00.009Z'),
    )

    Sequent.configuration.event_store.commit_events(
      TestAuditCommand.new(aggregate_id: aggregate_id_1),
      [
        [
          Sequent::Core::EventStream.new(
            aggregate_type: 'AuditTest',
            aggregate_id: aggregate_id_1,
          ),
          [audit_event],
        ],
      ],
    )

    caused_by_event = TestCausedByEvent.new(
      aggregate_id: aggregate_id_2,
      sequence_number: 1,
      created_at: Time.parse('2024-02-29T09:10.009Z'),
    )
    Sequent.configuration.event_store.commit_events(
      TestCausedByCommand.new(
        aggregate_id: aggregate_id_2,
        event_aggregate_id: audit_event.aggregate_id,
        event_sequence_number: audit_event.sequence_number,
      ),
      [
        [
          Sequent::Core::EventStream.new(
            aggregate_type: 'CausedByTest',
            aggregate_id: aggregate_id_2,
          ),
          [caused_by_event],
        ],
      ],
    )

    audit_command_record = Sequent::Core::CommandRecord.where(aggregate_id: aggregate_id_1).first
    audit_event_record = Sequent::Core::EventRecord.find_by_event(audit_event)
    caused_by_command_record = Sequent::Core::CommandRecord.where(aggregate_id: aggregate_id_2).first
    caused_by_event_record = Sequent::Core::EventRecord.find_by_event(caused_by_event)

    expect(audit_command_record.parent_event).to be_nil
    expect(audit_command_record.origin_command).to eq(audit_command_record)
    expect(audit_command_record.child_events.to_a).to include(audit_event_record)
    expect(audit_command_record.child_events.to_a).not_to include(caused_by_event_record)

    expect(audit_event_record.parent_command).to eq(audit_command_record)
    expect(audit_event_record.origin_command).to eq(audit_command_record)
    expect(audit_event_record.child_commands.to_a).to include(caused_by_command_record)

    expect(caused_by_command_record.parent_event).to eq(audit_event_record)
    expect(caused_by_command_record.origin_command).to eq(audit_command_record)
    expect(caused_by_command_record.child_events.to_a).to include(caused_by_event_record)
    expect(caused_by_command_record.child_events.to_a).not_to include(audit_event_record)

    expect(caused_by_event_record.parent_command).to eq(caused_by_command_record)
    expect(caused_by_event_record.parent_command.parent_event).to eq(audit_event_record)
    expect(caused_by_event_record.origin_command).to eq(audit_command_record)

    expect(caused_by_event_record.child_commands.to_a).to be_empty
  end
end
