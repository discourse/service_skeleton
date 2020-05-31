# frozen_string_literal: true

require_relative "../../spec_helper"

require "ultravisor/child"
require "ultravisor/error"

describe Ultravisor::Child do
	let(:child) { Ultravisor::Child.new(**args) }
	let(:mock_class) { Class.new.tap { |k| k.class_eval { def run; end; def sigterm; end } } }

	describe ".new" do
		context "with minimal arguments" do
			let(:args) { { id: :bob, klass: mock_class, method: :run } }

			it "does not explode" do
				expect { Ultravisor::Child.new(**args) }.to_not raise_error
			end

			it "does not instantiate an instance of klass" do
				expect(mock_class).to_not receive(:new)

				Ultravisor::Child.new(**args)
			end
		end

		context "with defined args" do
			let(:args) { { id: :bob, klass: mock_class, args: [foo: "bar"], method: :run } }

			it "explodes" do
				expect { Ultravisor::Child.new(**args) }.to raise_error(Ultravisor::InvalidKAMError)
			end
		end

		context "with a class that takes args" do
			let(:mock_class) { Class.new.tap { |k| k.class_eval { def initialize(*x); end } } }
			let(:args) { { id: :testy, klass: mock_class, args: [1, 2, 3], method: :to_s } }

			it "doesn't explode" do
				expect { Ultravisor::Child.new(**args) }.to_not raise_error
			end
		end

		context "with a non-existent method" do
			let(:args) { { id: :testy, klass: mock_class, method: :gogogo } }

			it "explodes" do
				expect { Ultravisor::Child.new(**args) }.to raise_error(Ultravisor::InvalidKAMError)
			end
		end

		context "with a method that takes args" do
			let(:args) { { id: :testy, klass: mock_class, method: :public_send } }

			it "explodes" do
				expect { Ultravisor::Child.new(**args) }.to raise_error(Ultravisor::InvalidKAMError)
			end
		end

		context "with a valid restart value" do
			it "is fine" do
				%i{always on_failure never}.each do |v|
					expect { Ultravisor::Child.new(id: :x, klass: Object, method: :to_s, restart: v) }.to_not raise_error
				end
			end
		end

		context "with an invalid restart value" do
			it "explodes" do
				[:sometimes, "always", 42, { max: 4 }].each do |v|
					expect { Ultravisor::Child.new(id: :x, klass: Object, method: :to_s, restart: v) }.to raise_error(ArgumentError)
				end
			end
		end

		context "with a valid restart_policy" do
			it "is happy" do
				expect do
					Ultravisor::Child.new(id: :rp, klass: Object, method: :to_s, restart_policy: { period: 5, max: 2, delay: 1 })
				end.to_not raise_error
			end
		end

		[
			{ when: :never },
			{ period: -1 },
			{ period: "never" },
			{ period: :sometimes },
			{ period: (0..10) },
			{ max: -1 },
			{ max: "powers" },
			{ max: (1..5) },
			{ delay: -1 },
			{ delay: "buses" },
			{ delay: (-1..3) },
			{ delay: (3..1) },
			"whenever you're ready",
		].each do |p|
			it "explodes with invalid restart_policy #{p.inspect}" do
				expect do
					Ultravisor::Child.new(id: :boom, klass: Object, method: :to_s, restart_policy: p)
				end.to raise_error(ArgumentError)
			end
		end

		context "with a valid shutdown spec" do
			it "is happy" do
				expect do
					Ultravisor::Child.new(id: :rp, klass: mock_class, method: :to_s, shutdown: { method: :sigterm, timeout: 2 })
				end.to_not raise_error
			end
		end

		[
			{ method: "man" },
			{ method: :send },
			{ method: :nonexistent_method },
			{ timeout: -4 },
			{ timeout: (3..5) },
			{ timeout: "MC Hammer" },
			{ woogiewoogie: "boo!" },
			"freddie!",
		].each do |s|
			it "explodes with invalid shutdown spec #{s.inspect}" do
				expect do
					Ultravisor::Child.new(id: :boom, klass: Object, method: :to_s, shutdown: s)
				end.to raise_error(ArgumentError)
			end
		end

		context "with castcall enabled" do
			it "is happy" do
				expect do
					Ultravisor::Child.new(id: :castcall, klass: Object, method: :to_s, enable_castcall: true)
				end.to_not raise_error
			end
		end

		[
			:bob,
			42,
			"unsafe",
			{ safe: :un },
		].each do |a|
			it "explodes with invalid access spec #{a.inspect}" do
				expect do
					Ultravisor::Child.new(id: :boom, klass: Object, method: :to_s, access: a)
				end.to raise_error(ArgumentError)
			end
		end
	end
end
