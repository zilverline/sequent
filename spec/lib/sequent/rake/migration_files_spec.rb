# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../../../../lib/sequent/rake/migration_files'

describe Sequent::Rake::MigrationFiles do
  around do |example|
    Dir.mktmpdir do |dir|
      @target = dir
      example.run
    end
  end

  let(:versions) do
    Dir.children(@target).grep(/\A\d+_.*\.rb\z/).map { |file| file.split('_').first }.sort
  end

  it 'gives every copied migration a valid timestamp when the copy crosses a minute' do
    Timecop.freeze(Time.new(2026, 10, 16, 12, 22, 50)) do
      Sequent::Rake::MigrationFiles.new.copy(@target)
    end

    expect(versions.first).to eq('20261016122250')
    expect(versions[10]).to eq('20261016122300')
    expect(versions).to eq(versions.uniq)
    versions.each do |version|
      expect(Time.strptime(version, '%Y%m%d%H%M%S').strftime('%Y%m%d%H%M%S')).to eq(version)
    end
  end
end
