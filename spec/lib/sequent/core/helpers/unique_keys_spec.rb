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

          unique_key :name, :country, scope: :country_of_residence
          unique_key :email, scope: :user_email
          unique_key :name_hash, scope: :user_name_hash

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
      end
    end
  end
end
