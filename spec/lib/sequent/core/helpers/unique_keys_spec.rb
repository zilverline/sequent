# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../lib/sequent/core/helpers/unique_keys'

module Sequent
  module Core
    module Helpers
      describe UniqueKeys do
        class TestUniqueKeys
          include UniqueKeys

          attr_reader :name, :country, :email

          unique_key :country_of_residence, :name, :country
          unique_key :user_email, email: -> { email&.downcase }
          unique_key :user_name_hash, name_hash: -> { name&.hash }

          def initialize(name:, country:, email:)
            @name = name
            @country = country
            @email = email
          end

          private

          def name_hash
            name&.hash
          end
        end

        let(:name) { 'bob' }
        let(:country) { 'NL' }
        let(:email) { 'bob@example.com' }

        subject { TestUniqueKeys.new(name:, country:, email:) }

        it 'uses accessors to generate the unique keys' do
          expect(subject.unique_keys).to eq(
            {
              country_of_residence: {name: 'bob', country: 'NL'},
              user_email: {email: 'bob@example.com'},
              user_name_hash: {name_hash: name.hash},
            },
          )
        end

        context 'nil values' do
          let(:country) { nil }
          let(:email) { nil }

          it 'leaves out attributes with a nil value' do
            expect(subject.unique_keys).to include(country_of_residence: {name: 'bob'})
          end

          it 'leaves out scopes with all nil values' do
            expect(subject.unique_keys).to_not include(:user_email)
          end
        end

        describe '.contains?' do
          # Each case was checked against PostgreSQL's jsonb @>.
          {
            [{a: 1, b: 2}, {a: 1}] => true,
            [{a: 1}, {a: 1, b: 2}] => false,
            [{a: {b: 1, c: 2}}, {a: {b: 1}}] => true,
            [{a: [1, 2]}, {a: [2]}] => true,
            [{a: [1, 2]}, {a: 2}] => false,
            [[1, 2], [2]] => true,
            [[1, [2, 3]], [[3]]] => true,
            [[1, [2, 3]], [3]] => false,
            [%w[a b], 'b'] => true,
            [%w[a b], 'c'] => false,
            [[%w[a b]], 'b'] => false,
            [[1, 2], 2.0] => true,
            %w[a a] => true,
            [{a: 1}, {}] => true,
            [{a: 1}, []] => false,
          }.each do |(value, partial), contained|
            it "#{contained ? 'finds' : 'does not find'} #{partial.to_json} in #{value.to_json}" do
              expect(UniqueKeys.contains?(value, partial)).to be(contained)
            end
          end
        end
      end
    end
  end
end
