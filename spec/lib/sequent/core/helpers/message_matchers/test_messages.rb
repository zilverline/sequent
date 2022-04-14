# frozen_string_literal: true

module TestModule; end

class SuperTestMessage < Sequent::Event; end

class TestMessage < SuperTestMessage
  include TestModule
end

class SubTestMessage < TestMessage; end

class OtherTestMessage < Sequent::Event; end
