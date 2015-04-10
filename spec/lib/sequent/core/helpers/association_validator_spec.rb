require 'spec_helper'

describe Sequent::Core::Helpers::AssociationValidator do

  let(:foo_list) { FooList.new }
  let(:foo_single) { FooSingle.new }

  it "should validate a single association" do
    foo_single.bar = Bar.new
    expect(foo_single.valid?).to be_falsey
  end


  it "should validate multiple associations" do
    foo_list.bar = Bar.new
    foo_list.other_bar = Bar.new

    expect(foo_list.valid?).to be_falsey
    expect(foo_list.errors).to have(2).items
    expect(foo_list.errors[:bar]).to have(1).items
    expect(foo_list.errors[:other_bar]).to have(1).items
  end

  it "should ignore association if nil" do
    expect(foo_list.valid?).to be_truthy
  end


  it "should validate both simple and complex associations with scoped names" do
    foo = FooWithNormalAttribute.new
    foo.bar = Bar.new
    expect(foo.valid?).to be_falsey
    expect(foo.errors).to have(2).items
    expect(foo.errors).to include(:bar)
    expect(foo.errors).to include(:name)
    expect(foo.bar.errors).to have(2).items
    expect(foo.bar.errors).to include(:first_name)
    expect(foo.bar.errors).to include(:last_name)
  end

  it "should validate an array" do
    foo_single.bar = [Bar.new]
    expect(foo_single.valid?).to be_falsey

    bar = Bar.new
    bar.first_name = "Ben"
    bar.last_name = "Vonk"
    foo_single.bar = [bar]
    expect(foo_single.valid?).to be_truthy
  end


end


class FooList
  include ActiveModel::Validations

  attr_accessor :bar, :other_bar

  validates_with Sequent::Core::Helpers::AssociationValidator, associations: [:bar, :other_bar]
end

class FooSingle
  include ActiveModel::Validations

  attr_accessor :bar

  validates_with Sequent::Core::Helpers::AssociationValidator, associations: :bar

end

class FooWithNormalAttribute
  include ActiveModel::Validations

  attr_accessor :bar, :name

  validates_presence_of :name

  validates_with Sequent::Core::Helpers::AssociationValidator, associations: :bar
end

class Bar
  include ActiveModel::Validations

  attr_accessor :first_name, :last_name
  validates_presence_of :first_name, :last_name

end
