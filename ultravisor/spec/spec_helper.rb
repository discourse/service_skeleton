require 'bundler'
Bundler.setup(:default, :development)
require 'rspec/core'
require 'rspec/mocks'

Thread.report_on_exception = false

require 'simplecov'
SimpleCov.start do
	add_filter('spec')
end

class ListIncompletelyCoveredFiles
	def format(result)
		incompletes = result.files.select { |f| f.covered_percent < 100 }

		unless incompletes.empty?
			puts
			puts "Files with incomplete test coverage:"
			incompletes.each do |f|
				printf "    %2.01f%%    %s\n", f.covered_percent, f.filename
			end
			puts; puts
		end
	end
end

SimpleCov.formatters = SimpleCov::Formatter::MultiFormatter.new([
	SimpleCov::Formatter::HTMLFormatter,
	ListIncompletelyCoveredFiles
])

require_relative "./example_group_methods"
require_relative "./example_methods"

RSpec.configure do |config|
	config.extend ExampleGroupMethods
	config.include ExampleMethods

	config.order = :random
	config.fail_fast = !!ENV["RSPEC_CONFIG_FAIL_FAST"]
	config.full_backtrace = !!ENV["RSPEC_CONFIG_FULL_BACKTRACE"]

	config.expect_with :rspec do |c|
		c.syntax = :expect
	end

	config.mock_with :rspec do |mocks|
		mocks.verify_partial_doubles = true
	end
end
