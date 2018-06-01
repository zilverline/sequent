require 'spec_helper'
require 'fileutils'

describe Sequent::Generator::Command do
  let(:app_name) { 'blog' }
  let(:arg) { 'address' }
  let(:tmp_path) { "tmp/sequent-generator-spec" }
  let(:app_dir) { [tmp_path, app_name].join('/') }

  subject(:execute) { Sequent::Generator::Command.new(arg, 'SetStreet', ['street:string']).execute }

  around do |example|
    FileUtils.mkdir_p(tmp_path)
    Sequent::Generator::Project.new(app_dir).execute
    Dir.chdir(app_dir) do
      Sequent::Generator::Aggregate.new(arg).execute
      example.run
    end
    FileUtils.rmtree(tmp_path)
  end

  it 'adds the command' do
    execute
    expect(File.read('lib/address/commands.rb')).to include("SetStreet")
    expect(File.read('lib/address/commands.rb')).to include("attrs street: String")
  end
end
