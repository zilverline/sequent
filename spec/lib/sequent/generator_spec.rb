require 'spec_helper'
require 'fileutils'

describe Sequent::Generator do
  let(:tmp_path) { 'tmp/sequent-generator-spec' }

  around do |example|
    FileUtils.rmtree(tmp_path)
    FileUtils.mkdir_p(tmp_path)
    Dir.chdir(tmp_path) { example.run }
  end

  let(:arg) { 'blog' }
  let(:path) { File.expand_path(arg) }
  subject(:execute) { Sequent::Generator.new(arg).execute }

  it 'creates a directory with the given name' do
    expect { subject }.to change { File.directory?(path) }.from(false).to(true)
  end

  context 'with an absolute path' do
    let(:arg) { '~/tmp/non_existent_thingy' }
    before { FileUtils.rmtree(path) }

    it 'creates a directory on the absolute path' do
      expect { subject }.to change { File.directory?(path) }.from(false).to(true)
    end
  end

  it 'copies the generator files' do
    execute
    expect(FileUtils.cmp('blog/Gemfile', '../../lib/sequent/generator/template_project/Gemfile')).to be_truthy
  end

  it 'names the app' do
    execute
    expect(File.exist?('blog/my_app.rb')).to be_falsey
    expect(File.exist?('blog/blog.rb')).to be_truthy
    expect(File.read('blog/blog.rb')).to_not include('module MyApp')
    expect(File.read('blog/blog.rb')).to include('module Blog')
    expect(File.read('blog/Rakefile')).to_not include("require './my_app'")
    expect(File.read('blog/Rakefile')).to include("require './blog'")
  end

  xit 'has working example with specs' do
    execute

    Bundler.with_clean_env do
      system 'bash', '-cex', <<~SCRIPT
        cd blog
        export RACK_ENV=test
        source ~/.bash_profile

        if which rbenv; then
          rbenv shell $(cat ./.ruby-version)
          rbenv install --skip-existing
        fi

        gem install bundler
        bundle install
        bundle exec rake db:drop db:create db:migrate view_schema:build
        bundle exec rspec spec
      SCRIPT

      expect($?.to_i).to eq(0)
    end
  end
end
