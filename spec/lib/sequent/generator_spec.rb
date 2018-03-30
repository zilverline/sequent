require 'spec_helper'
require 'fileutils'

describe Sequent::Generator do
  let(:tmp_path) { 'tmp/sequent-generator-spec' }

  around do |example|
    FileUtils.mkdir_p(tmp_path)
    Dir.chdir(tmp_path) { example.run }
    FileUtils.rmtree(tmp_path)
  end

  subject(:execute) { Sequent::Generator.new('blog').execute }

  it 'creates a directory with the given name' do
    expect { subject }.to change { File.directory?('blog') }.from(false).to(true)
  end

  it 'copies the generator files' do
    execute
    expect(FileUtils.cmp('blog/Gemfile', '../../lib/sequent/generator/template_project/Gemfile')).to be_truthy
  end

  it 'has working example with specs' do
    execute
    system 'cd blog  && rspec spec'
    expect($?.to_i).to eq(0)
  end
end
