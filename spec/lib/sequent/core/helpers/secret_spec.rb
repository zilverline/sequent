require 'spec_helper'

class SecretCommand < Sequent::Core::Command

  def initialize(args = {})
    super({aggregate_id: '1', name: 'Jari'}.merge(args))
  end

  attrs password: Sequent::Secret, name: String

  validates_presence_of :name
end

describe 'commands with secrets' do
  it 'handles nil' do
    command = SecretCommand.new(password: nil)
    command.valid?

    command = command.parse_attrs_to_correct_types
    expect(command.password).to be_nil
  end

  context 'with strings' do
    it 'can set a secret' do
      command = SecretCommand.new(password: 'foo')
      expect(command.password).to eq 'foo'
    end

    it 'empties the secret when command is invalid' do
      command = SecretCommand.new(password: 'foo', name: nil)
      expect(command.password).to eq 'foo'

      command.valid?
      expect(command.password).to be_nil
    end

    it 'encrypts the password after validation' do
      command = SecretCommand.new(password: 'foo', name: 'jari')
      command.valid?

      parsed_command = command.parse_attrs_to_correct_types

      expect(parsed_command.password).to be_a(Sequent::Secret)
      expect(parsed_command.password.verify_secret('foo')).to be_truthy
      expect(parsed_command.password.verify_secret('f00')).to be_falsey
    end
  end

  context 'with Sequent::Secret' do
    it 'can set a secret' do
      command = SecretCommand.new(password: Sequent::Secret.new('foo'))
      expect(command.password).to eq Sequent::Secret.new('foo')
    end

    it 'encrypts the password after validation' do
      command = SecretCommand.new(password: Sequent::Secret.new('foo'), name: 'jari')
      command.valid?

      parsed_command = command.parse_attrs_to_correct_types

      expect(parsed_command.password).to be_a(Sequent::Secret)
      expect(parsed_command.password.verify_secret('foo')).to be_truthy
      expect(parsed_command.password.verify_secret('f00')).to be_falsey
    end
  end
end
