# frozen_string_literal: true

require 'spec_helper'

module ApplyHooksSpec
  class Created < Sequent::Event; end

  class Changed < Sequent::Event
    attrs value: Integer
  end

  class SpecialChanged < Changed; end
  class Ignored < Sequent::Event; end

  class Root < Sequent::AggregateRoot
    attr_reader :value

    before_apply { |event| calls << [:before_block, event.class] }
    before_apply :record_before, only: Changed
    before_apply(only: is_a(Changed)) { |event| calls << [:before_is_a, event.class] }
    around_apply :record_around, except: [Ignored]
    around_apply do |event, continuation|
      calls << [:around_block_in, event.class]
      continuation.call
      calls << [:around_block_out, event.class]
    end
    after_apply { |event| calls << [:after, event.class, @value] }

    def initialize(id)
      super
      apply Created
    end

    def change(value, event_class: Changed)
      apply event_class, value:
    end

    def ignore
      apply Ignored
    end

    def calls
      @calls ||= []
    end

    def record_before(event)
      calls << [:before_method, event.class]
    end

    def record_around(event)
      calls << [:around_method_in, event.class]
      yield
      calls << [:around_method_out, event.class]
    end

    on Changed do |event|
      @value = event.value
      calls << [:applied, event.value]
    end
  end

  class Matching < Sequent::AggregateRoot
    def change(value)
      apply Changed, value:
    end

    def calls
      @calls ||= []
    end

    after_apply(only: has_attrs(Changed, value: 2)) { |event| calls << [:after_has_attrs, event.value] }
  end

  class SubRoot < Root
    after_apply { |event| calls << [:sub_after, event.class] }
  end

  class Guarded < Sequent::AggregateRoot
    attr_reader :value

    before_apply(only: Changed) { |event| fail 'negative' if event.value.negative? }
    around_apply(only: Ignored) { |_event, _continuation| nil }

    def change(value)
      apply Changed, value:
    end

    def ignore
      apply Ignored
    end

    on Changed do |event|
      @value = event.value
    end
  end
end

describe Sequent::Core::Helpers::ApplyHooks do
  let(:id) { Sequent.new_uuid }
  let(:root) { ApplyHooksSpec::Root.new(id).tap { |root| root.calls.clear } }

  it 'runs the before, around and after hooks in order around applying the event' do
    root.change(1)

    expect(root.calls).to eq(
      [
        [:before_block, ApplyHooksSpec::Changed],
        [:before_method, ApplyHooksSpec::Changed],
        [:before_is_a, ApplyHooksSpec::Changed],
        [:around_method_in, ApplyHooksSpec::Changed],
        [:around_block_in, ApplyHooksSpec::Changed],
        [:applied, 1],
        [:around_block_out, ApplyHooksSpec::Changed],
        [:around_method_out, ApplyHooksSpec::Changed],
        [:after, ApplyHooksSpec::Changed, 1],
      ],
    )
  end

  it 'runs a hook only for the events of only, and not for those of except' do
    root.ignore

    expect(root.calls).to eq(
      [
        [:before_block, ApplyHooksSpec::Ignored],
        [:around_block_in, ApplyHooksSpec::Ignored],
        [:around_block_out, ApplyHooksSpec::Ignored],
        [:after, ApplyHooksSpec::Ignored, nil],
      ],
    )
  end

  it 'does not match the subclasses of a class in only' do
    root.change(1, event_class: ApplyHooksSpec::SpecialChanged)

    expect(root.calls).not_to include([:before_method, ApplyHooksSpec::SpecialChanged])
  end

  it 'matches the subclasses with is_a in only' do
    root.change(1)
    root.change(1, event_class: ApplyHooksSpec::SpecialChanged)

    expect(root.calls.select { |call| call.first == :before_is_a })
      .to eq([[:before_is_a, ApplyHooksSpec::Changed], [:before_is_a, ApplyHooksSpec::SpecialChanged]])
  end

  it 'matches the attributes of has_attrs in only' do
    matching = ApplyHooksSpec::Matching.new(id)

    matching.change(1)
    expect(matching.calls).to be_empty
    matching.change(2)
    expect(matching.calls).to eq([[:after_has_attrs, 2]])
  end

  it 'does not run the hooks when loading the aggregate' do
    root.change(1)

    loaded = ApplyHooksSpec::Root.load_from_history(:stream, root.uncommitted_events)

    expect(loaded.value).to eq(1)
    expect(loaded.calls).to eq([[:applied, 1]])
  end

  it 'runs the inherited hooks before those of the subclass' do
    sub_root = ApplyHooksSpec::SubRoot.new(id)
    sub_root.calls.clear

    sub_root.change(1)

    expect(sub_root.calls.map(&:first).last(2)).to eq(%i[after sub_after])
    root.change(1)
    expect(root.calls.map(&:first)).not_to include(:sub_after)
  end

  it 'does not apply the event when a hook raises' do
    guarded = ApplyHooksSpec::Guarded.new(id)

    expect { guarded.change(-1) }.to raise_error('negative')
    expect(guarded.value).to be_nil
    expect(guarded.uncommitted_events).to be_empty
  end

  it 'fails when an around hook does not apply the event' do
    guarded = ApplyHooksSpec::Guarded.new(id)

    expect { guarded.ignore }.to raise_error(/around_apply hook .* did not apply ApplyHooksSpec::Ignored/)
    expect(guarded.uncommitted_events).to be_empty
  end

  context 'declaring hooks' do
    it 'requires either a method name or a block' do
      expect { Class.new(Sequent::AggregateRoot) { before_apply } }
        .to raise_error(ArgumentError, /requires either a method name or a block/)
      expect { Class.new(Sequent::AggregateRoot) { before_apply(:foo) { nil } } }
        .to raise_error(ArgumentError, /requires either a method name or a block/)
    end

    it 'takes either only or except' do
      expect do
        Class.new(Sequent::AggregateRoot) do
          after_apply :foo, only: ApplyHooksSpec::Changed, except: ApplyHooksSpec::Ignored
        end
      end.to raise_error(ArgumentError, /takes either only or except/)
    end

    it 'takes the same arguments as on' do
      expect { Class.new(Sequent::AggregateRoot) { around_apply :foo, only: 'String' } }
        .to raise_error(ArgumentError, /Can't coerce argument/)
    end
  end
end
