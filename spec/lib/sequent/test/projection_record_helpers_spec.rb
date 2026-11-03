# frozen_string_literal: true

require 'spec_helper'
require 'sequent/test/projection_record_helpers'

describe Sequent::Test::ProjectionRecordHelpers do
  def projection_record_class(&block)
    Class.new(Sequent::ApplicationRecord) do
      self.table_name = 'projection_record_helpers_records'
      include Sequent::Core::ProjectionRecord

      class_eval(&block) if block
    end
  end

  def write_callbacks(allow: [], &block) = described_class.write_callbacks(projection_record_class(&block), allow:)

  it 'accepts a record class without callbacks, with associations and callbacks that run when reading' do
    record_class = projection_record_class do
      has_many :others, class_name: name, foreign_key: :aggregate_id, primary_key: :aggregate_id
      has_one :other, class_name: name, foreign_key: :aggregate_id, primary_key: :aggregate_id
      after_find { nil }
      after_initialize { nil }
    end

    expect(record_class).to have_no_write_callbacks
  end

  it 'describes the callbacks that run when writing and the validations' do
    expect(write_callbacks { before_save :normalize_name }).to eq ['before_save normalize_name']
    expect(write_callbacks { after_commit { nil } }).to eq ['after_commit (block)']
    expect(write_callbacks { before_commit :notify }).to eq ['before_commit notify']
    expect(write_callbacks { validates :name, presence: true })
      .to eq ['ActiveRecord::Validations::PresenceValidator name']
    expect(write_callbacks { belongs_to :parent, class_name: 'Object', optional: false })
      .to eq ['ActiveRecord::Validations::PresenceValidator parent']
  end

  it 'accepts the allowed callbacks and validators' do
    allow = [:normalize_name, /\Aaudit_/, ActiveModel::Validations::PresenceValidator]

    expect(
      write_callbacks(allow:) do
        before_save :normalize_name
        after_save :audit_changes
        validates :name, presence: true
        before_save :other
      end,
    ).to eq ['before_save other']
  end

  it 'fails with the callbacks of the record class' do
    record_class = projection_record_class { before_save :normalize_name }

    expect { expect(record_class).to have_no_write_callbacks }
      .to raise_error(RSpec::Expectations::ExpectationNotMetError, /it has: before_save normalize_name/)
    expect(record_class).to have_no_write_callbacks(allow: [:normalize_name])
  end
end
