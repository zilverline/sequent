# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::Projectors do
  subject { Sequent::Core::Projectors }
  class SomeProjectorClass < Sequent::Core::Projector
    self.skip_autoregister = true
  end
  class AnotherProjectorClass < Sequent::Core::Projector
    self.skip_autoregister = true
  end

  context 'registration' do
    it 'manages active projector registrations' do
      subject.register_inactive_projectors!([SomeProjectorClass, AnotherProjectorClass])
      expect(subject.projector_states).to include(
        'SomeProjectorClass' => have_attributes(active_version: nil),
        'AnotherProjectorClass' => have_attributes(active_version: nil),
      )

      subject.register_active_projectors!([SomeProjectorClass, AnotherProjectorClass])
      expect(subject.projector_states).to include(
        'SomeProjectorClass' => have_attributes(active_version: 1),
        'AnotherProjectorClass' => have_attributes(active_version: 1),
      )

      subject.deactivate_unknown_projectors!(known_projector_classes: [AnotherProjectorClass])
      expect(subject.projector_states).to include(
        'SomeProjectorClass' => have_attributes(active_version: nil),
        'AnotherProjectorClass' => have_attributes(active_version: 1),
      )
    end
  end
end
