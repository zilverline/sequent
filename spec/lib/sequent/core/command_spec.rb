# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::BaseCommand do
  it 'includes TypeConversion' do
    expect(Sequent::Core::BaseCommand.included_modules).to include(Sequent::Core::Helpers::TypeConversionSupport)
  end

  context Sequent::Core::Command do
    it 'can be constructed with an aggregate_id and organization_id' do
      command = Sequent::Core::Command.new(aggregate_id: 'abc')
      expect(command.aggregate_id).to eq 'abc'
    end

    it 'fails fast when not constructed with an aggregate_id' do
      expect { Sequent::Core::Command.new }.to raise_error(/Missing aggregate_id/)
    end

    it 'after_initialize works' do
      class AfterInitCommand < Sequent::Command
        attrs flag: Boolean

        after_initialize do
          @flag = true if @flag.nil?
        end
      end

      cmd = AfterInitCommand.new(aggregate_id: Sequent.new_uuid)
      expect(cmd.flag).to eq true
    end

    context 'validations' do
      class ValidationCommand < Sequent::Command
        attrs flag: Boolean,
              number: Integer,
              date_time: DateTime,
              date: Date
      end

      let(:command) do
        ValidationCommand.new(
          aggregate_id: Sequent.new_uuid,
          flag: true,
          number: 10,
          date_time: DateTime.now,
          date: Date.today,
        )
      end

      context Boolean do
        it 'validates booleans' do
          expect(command.copy(flag: 'foobar')).to_not be_valid
          expect(command.copy(flag: '0')).to_not be_valid
          expect(command.copy(flag: '')).to be_valid
          expect(command.copy(flag: 'true')).to be_valid
          expect(command.copy(flag: true)).to be_valid
          expect(command.copy(flag: false)).to be_valid
          expect(command.copy(flag: 'false')).to be_valid
          expect(command.copy(flag: nil)).to be_valid
        end
      end

      context Date do
        it 'validates dates' do
          expect(command.copy(date: '09-10-2018')).to_not be_valid
          expect(command.copy(date: 'foobar')).to_not be_valid
          expect(command.copy(date: '2018-09-10')).to be_valid
          expect(command.copy(date: Date.today)).to be_valid
          expect(command.copy(date: nil)).to be_valid
        end
      end

      context DateTime do
        it 'validates date times' do
          expect(command.copy(date_time: '09-10-2018T12:13:14')).to_not be_valid
          expect(command.copy(date_time: 'foobar')).to_not be_valid
          expect(command.copy(date_time: '2018-09-10T13:12:11')).to be_valid
          expect(command.copy(date_time: DateTime.now)).to be_valid
          expect(command.copy(date_time: nil)).to be_valid
          expect(command.copy(date_time: '   ')).to be_valid
        end
      end

      context Integer do
        it 'validates integers' do
          expect(command.copy(number: 'foobar')).to_not be_valid
          expect(command.copy(number: '10.19')).to_not be_valid
          expect(command.copy(number: '  ')).to be_valid
          expect(command.copy(number: '010')).to be_valid
          expect(command.copy(number: 10)).to be_valid
          expect(command.copy(number: nil)).to be_valid
        end
      end
    end
  end

  context Sequent::Core::UpdateCommand do
    it 'fails when no sequence number is given' do
      expect(Sequent::Core::UpdateCommand.new(aggregate_id: 'foo').valid?).to be_falsey
    end

    it 'is valid when sequence number is given' do
      expect(Sequent::Core::UpdateCommand.new(aggregate_id: 'foo', sequence_number: 1).valid?).to be_truthy
    end
  end

  context Sequent::Core::UpdateCommand do
    it 'fails when no sequence number is given' do
      expect(Sequent::Core::UpdateCommand.new(aggregate_id: 'foo').valid?).to be_falsey
    end

    it 'is valid when sequence number is given' do
      expect(Sequent::Core::UpdateCommand.new(aggregate_id: 'foo', sequence_number: 1).valid?).to be_truthy
    end
  end

  context Sequent::Core::Commands do
    it 'registers subclasses of Sequent::Core::Command' do
      expect(Sequent::Core::Commands.find('Sequent::Core::UpdateCommand')).to eq Sequent::Core::UpdateCommand
    end

    it 'does not find any other object' do
      expect(Sequent::Core::Commands.find('String')).to eq nil
    end
  end
end
