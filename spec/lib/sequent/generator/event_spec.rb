# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

describe Sequent::Generator::Event do
  let(:app_name) { 'blog' }
  let(:arg) { 'address' }
  let(:tmp_path) { 'tmp/sequent-generator-spec' }
  let(:app_dir) { [tmp_path, app_name].join('/') }

  subject(:execute) { Sequent::Generator::Event.new(arg, 'StreetSet', ['street:string']).execute }

  around do |example|
    FileUtils.mkdir_p(tmp_path)
    Sequent::Generator::Project.new(app_dir).execute
    Dir.chdir(app_dir) do
      Sequent::Generator::Aggregate.new(arg).execute
      example.run
    end
    FileUtils.rmtree(tmp_path)
  end

  it 'adds the event and handlers' do
    execute
    expect(File.read('lib/address/events.rb')).to include('StreetSet')
    expect(File.read('lib/address/events.rb')).to include('attrs street: String')
    expect(File.read('lib/address/address.rb')).to include('StreetSet')
  end
end
