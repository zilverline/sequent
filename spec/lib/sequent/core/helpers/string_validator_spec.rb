require 'spec_helper'

describe Sequent::Core::Helpers::StringValidator do
  class StringValidatorCommand < Sequent::Command
    def initialize(args)
      super(args.merge(aggregate_id: '1'))
    end

    attrs name: String
  end

  it 'Anything that can be to_s-ed is a valid string' do
    command = StringValidatorCommand.new(name: 1)
    command.valid?
    expect(command.errors[:name]).to be_empty
    expect(command.valid?).to be_truthy
  end

  it 'String can be nil' do
    command = StringValidatorCommand.new(name: nil)

    expect(command.valid?).to be_truthy
  end

  it 'String can not nil chars' do
    command = StringValidatorCommand.new(name: "foo \u0000")

    expect(command.valid?).to_not be_truthy
    expect(command.errors[:name]).to_not be_empty
  end
end
