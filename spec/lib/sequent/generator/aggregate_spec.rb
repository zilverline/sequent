require 'spec_helper'
require 'fileutils'

describe Sequent::Generator::Aggregate do
  let(:app_name) { 'blog' }
  let(:arg) { 'address' }
  let(:tmp_path) { "tmp/sequent-generator-spec" }
  let(:app_dir) { [tmp_path, app_name].join('/') }

  subject(:execute) { Sequent::Generator::Aggregate.new(arg).execute }

  around do |example|
    FileUtils.mkdir_p(tmp_path)
    Sequent::Generator::Project.new(app_dir).execute
    Dir.chdir(app_dir) do
      example.run
    end
    FileUtils.rmtree(tmp_path)
  end

  it 'creates a directory for the new aggregate' do
    expect { subject }.to change { File.directory?("lib/#{arg}") }.from(false).to(true)
  end

  it 'correctly copies the files' do
    execute
    expect(File.exist?('lib/template_aggregate.rb')).to be_falsey
    expect(File.exist?('lib/address.rb')).to be_truthy
    expect(File.directory?('lib/template_aggregate')).to be_falsey
    expect(File.directory?('lib/address')).to be_truthy
    expect(File.read('lib/address.rb')).to_not include("require_relative 'template_aggregate/commands'")
    expect(File.read('lib/address.rb')).to include("require_relative 'address/commands'")
    expect(File.read('lib/address/commands.rb')).to_not include('AddTemplateAggregate')
    expect(File.read('lib/address/commands.rb')).to include('AddAddress')
  end
end
