begin
	require "git-version-bump"
rescue LoadError
	nil
end

Gem::Specification.new do |s|
	s.name = "ultravisor"

	s.version = GVB.version rescue "0.0.0.1.NOGVB"
	s.date    = GVB.date    rescue Time.now.strftime("%Y-%m-%d")

	s.platform = Gem::Platform::RUBY

	s.summary  = "A template gem"

	s.authors  = ["Matt Palmer"]
	s.email    = ["theshed+ultravisor@hezmatt.org"]
  s.homepage = "https://github.com/mpalmer/ultravisor"

	s.files = `git ls-files -z`.split("\0").reject { |f| f =~ /^(G|spec|Rakefile)/ }

  s.required_ruby_version = ">= 2.3.0"


	s.add_development_dependency "bundler"
	s.add_development_dependency "github-release"
	s.add_development_dependency "guard-rspec"
	s.add_development_dependency "rake", "~> 10.4", ">= 10.4.2"
	# Needed for guard
	s.add_development_dependency "rb-inotify", "~> 0.9"
	s.add_development_dependency "redcarpet"
	s.add_development_dependency "rspec"
  s.add_development_dependency "simplecov"
	s.add_development_dependency "yard"
end
