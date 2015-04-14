require 'spec_helper'

describe Sequent::Core::BaseCommand do

  it "includes TypeConversion" do
    expect(Sequent::Core::BaseCommand.included_modules).to include(Sequent::Core::Helpers::TypeConversionSupport)
  end

  context Sequent::Core::TenantCommand do

    it "can be constructed with an aggregate_id and organization_id" do
      command = Sequent::Core::TenantCommand.new(aggregate_id: "abc", organization_id: "xyz")
      expect(command.aggregate_id).to eq "abc"
      expect(command.organization_id).to eq "xyz"
    end

    it "fails fast when not constructed with an aggregate_id" do
      expect { Sequent::Core::TenantCommand.new(organization_id: "xyz") }.to raise_error(/Missing aggregate_id/)
    end

    it "fails fast when not constructed with an organization_id" do
      expect { Sequent::Core::TenantCommand.new(aggregate_id: "abc") }.to raise_error(/Missing organization_id/)
    end

  end

  context Sequent::Core::UpdateTenantCommand do
    it "fails when no sequence number is given" do
      expect(Sequent::Core::UpdateTenantCommand.new(aggregate_id: "foo", organization_id: "bar").valid?).to be_falsey
    end

    it "is valid when sequence number is given" do
      expect(Sequent::Core::UpdateTenantCommand.new(aggregate_id: "foo", organization_id: "bar", sequence_number: 1).valid?).to be_truthy
    end

  end

  context Sequent::Core::UpdateCommand do

    it "fails when no sequence number is given" do
      expect(Sequent::Core::UpdateCommand.new(aggregate_id: "foo").valid?).to be_falsey
    end

    it "is valid when sequence number is given" do
      expect(Sequent::Core::UpdateCommand.new(aggregate_id: "foo", sequence_number: 1).valid?).to be_truthy
    end
  end

end
