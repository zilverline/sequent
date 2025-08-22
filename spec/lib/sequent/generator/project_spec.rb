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

    contents = File.read('blog-with_special-symbols/Gemfile')
    File.write(
      'blog-with_special-symbols/Gemfile',
      contents.lines.map do |line|
        if line =~ /sequent/
          "gem 'sequent', path: '../../..'\n"
        else
          line
        end
      end.join,
    )

    Bundler.with_unbundled_env do
      system 'bash', '-cex', <<~SCRIPT
        cd blog-with_special-symbols
        export SEQUENT_ENV=test
        export BUNDLE_GEMFILE=./Gemfile
        export PGUSER=sequent
        export PGPASSWORD=sequent

        ruby_version=$(ruby -v | awk '{print $2}' | grep -o '^[0-9.]*')
        echo "$ruby_version" > .ruby-version

        export BUNDLE_GEMFILE=./Gemfile
        gem install bundler
        bundle config set local.sequent ../../..
        bundle config
        bundle install
        bundle exec rake sequent:db:drop
        bundle exec rake sequent:db:migrate
        bundle exec rake sequent:projectors:replay:all
        bundle exec rspec spec
      SCRIPT

      # rubocop:disable Style/SpecialGlobalVars
      expect($?.to_i).to eq(0)
      # rubocop:enable Style/SpecialGlobalVars
    end
  end
end
