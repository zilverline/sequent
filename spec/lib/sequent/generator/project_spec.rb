# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

describe Sequent::Generator::Project do
  let(:tmp_path) { 'tmp/sequent-generator-spec' }

  around do |example|
    FileUtils.rmtree(tmp_path)
    FileUtils.mkdir_p(tmp_path)
    Dir.chdir(tmp_path) { example.run }
  end

  let(:arg) { 'blog-with_special-symbols' }
  let(:path) { File.expand_path(arg) }
  subject(:execute) { Sequent::Generator::Project.new(arg).execute }

  it 'creates a directory with the given name' do
    execute
    expect(Pathname.new(path)).to be_directory
  end

  context 'with an absolute path' do
    let(:arg) { '~/tmp/non_existent_thingy' }
    before { FileUtils.rmtree(path) }

    it 'creates a directory on the absolute path' do
      execute
      expect(Pathname.new(path)).to be_directory
    end
  end

  it 'copies the generator files' do
    execute
    expect(
      FileUtils.cmp(
        'blog-with_special-symbols/Gemfile',
        '../../lib/sequent/generator/template_project/Gemfile',
      ),
    ).to be_truthy
  end

  it 'copies the ruby-version to .ruby-version' do
    execute
    expect(Pathname.new('blog-with_special-symbols/.ruby-version')).to exist
  end

  it 'names the app' do
    execute
    expect(Pathname('blog-with_special-symbols/my_app.rb')).not_to exist
    expect(Pathname('blog-with_special-symbols/blog_with_special_symbols.rb')).to exist
    expect(File.read('blog-with_special-symbols/blog_with_special_symbols.rb')).not_to include('module MyApp')
    expect(
      File.read('blog-with_special-symbols/blog_with_special_symbols.rb'),
    ).to include('module BlogWithSpecialSymbols')
    expect(File.read('blog-with_special-symbols/Rakefile')).to_not include("require './my_app'")
    expect(File.read('blog-with_special-symbols/Rakefile')).to include("require './blog_with_special_symbols'")
  end

  it 'has working example with specs' do
    execute

    Bundler.with_unbundled_env do
      # Change default database configuration
      Sequent.configuration.database_config_directory = File.join(path, 'db')
      Database.write_database_yml_for_test(env: 'test', database_name: 'blog_with_special_symbols_test')

      system 'bash', '-cex', <<~SCRIPT
        cd blog-with_special-symbols
        export SEQUENT_ENV=test

        ruby_version=$(ruby -v | awk '{print $2}' | grep -o '^[0-9.]*')
        echo "$ruby_version" > .ruby-version

        gem install bundler
        bundle install
        bundle exec rake sequent:db:drop
        bundle exec rake sequent:db:create
        bundle exec rake sequent:db:create_view_schema
        bundle exec rake sequent:migrate:online
        bundle exec rake sequent:migrate:offline
        bundle exec rspec spec
      SCRIPT

      # rubocop:disable Style/SpecialGlobalVars
      expect($?.to_i).to eq(0)
      # rubocop:enable Style/SpecialGlobalVars
    end
  end
end
