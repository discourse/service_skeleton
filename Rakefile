# frozen_string_literal: true

exec(*(["bundle", "exec", $PROGRAM_NAME] + ARGV)) if ENV['BUNDLE_GEMFILE'].nil?

task default: :test
task default: :rubocop
task default: :doc_stats

begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end

require 'yard'

task :rubocop do
  sh "rubocop --fail-level R"
end

YARD::Rake::YardocTask.new :doc do |yardoc|
  yardoc.files = %w{lib/**/*.rb - README.md CONTRIBUTING.md CODE_OF_CONDUCT.md}
end

task :doc_stats do
  sh "yard stats --list-undoc"
end

desc "Run guard"
task :guard do
  sh "guard --clear"
end

require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new :test do |t|
  t.pattern = ["spec/**/*_spec.rb", "ultravisor/spec/**/*_spec.rb"]
end

class Bundler::GemHelper
  def already_tagged?
    true
  end
end

Bundler::GemHelper.install_tasks
