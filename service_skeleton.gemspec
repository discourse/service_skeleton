# frozen_string_literal: true

begin
  require 'git-version-bump'
rescue LoadError
  nil
end

Gem::Specification.new do |s|
  s.name = "service_skeleton"

  s.version = GVB.version rescue "0.0.0.1.NOGVB"
  s.date    = GVB.date    rescue Time.now.strftime("%Y-%m-%d")

  s.platform = Gem::Platform::RUBY

  s.summary  = "The bare bones of a service"
  s.description = <<~EOF
    When you need to write a program that provides some sort of persistent
    service, there are some things you always need.  Logging, metrics,
    extracting configuration from the environment, signal handling, and so on.
    This gem provides ServiceSkeleton, a template class you can use as a base
    for your services, as well as a collection of helper classes to manage
    common aspects of a system service.
  EOF

  s.authors  = ["Matt Palmer"]
  s.email    = ["matt.palmer@discourse.org"]
  s.homepage = "https://github.com/discourse/service_skeleton"

  s.files = `git ls-files -z`.split("\0").reject { |f| f =~ /^(G|spec|Rakefile)/ }

  s.required_ruby_version = ">= 2.5.0"

  s.add_runtime_dependency "frankenstein", "~> 2.0"
  s.add_runtime_dependency "loggerstash", ">= 0.0.9", "< 1"
  s.add_runtime_dependency "prometheus-client", "~> 2.0"
  s.add_runtime_dependency "sigdump", "~> 0.2"
  s.add_runtime_dependency "to_regexp", "~> 0.2"
  s.add_runtime_dependency "ultravisor", "~> 0.a"

  s.add_development_dependency 'bundler'
  s.add_development_dependency 'github-release'
  s.add_development_dependency 'git-version-bump'
  s.add_development_dependency 'guard-rspec'
  s.add_development_dependency 'guard-rubocop'
  s.add_development_dependency 'rack-test'
  s.add_development_dependency 'rake', "~> 12.0"
  s.add_development_dependency 'redcarpet'
  s.add_development_dependency 'rspec'
  s.add_development_dependency 'rubocop', "~> 0.79"
  s.add_development_dependency 'rubocop-discourse'
  s.add_development_dependency 'simplecov'
  s.add_development_dependency 'yard'
end
