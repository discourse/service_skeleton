# frozen_string_literal: true

require_relative "../../spec_helper"

require "service_skeleton"

describe ServiceSkeleton::ConfigVariables do
  let(:klass) { Class.new.include(ServiceSkeleton) }

  def variable(env)
    rego = klass
      .registered_variables
      .find { |r| r[:name] == var_name }
    rego[:class].new(rego[:name], env, **rego[:opts])
  end

  describe "enum" do
    let(:var_name) { :MY_ENUM }

    it "explodes if no values option is provided" do
      expect { klass.enum(var_name) }.to raise_error(ArgumentError)
    end

    it "explodes if the values option isn't an acceptable type" do
      expect { klass.enum(var_name, values: "Judeo-Christian") }.to raise_error(ArgumentError)
    end

    it "accepts an array of string values" do
      klass.enum(var_name, values: %w{one two three})
      expect(klass.registered_variables).to include(name: :MY_ENUM, class: ServiceSkeleton::ConfigVariable::Enum, opts: { sensitive: false, values: ["one", "two", "three"] })
    end

    it "accepts a hash of string => object pairs" do
      klass.enum(var_name, values: { "one" => 1, "two" => 2, "three" => 3 })
      expect(klass.registered_variables).to include(name: :MY_ENUM, class: ServiceSkeleton::ConfigVariable::Enum, opts: { sensitive: false, values: { "one" => 1, "two" => 2, "three" => 3 } })
    end

    describe "variable object" do
      before(:each) do
        klass.enum(:MY_ENUM, **opts)
      end

      context "with array of values" do
        let(:opts) { { values: %w{one two three} } }

        %w{one two three}.each do |s|
          it "sets the matching value #{s}" do
            expect(variable("MY_ENUM" => s).value).to eq(s)
          end
        end

        %w{foo bar baz}.each do |s|
          it "rejects invalid enum value #{s} with an exception" do
            expect { variable("MY_ENUM" => s) }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
          end
        end

        it "raises an exception if no variable given" do
          expect { variable("FOO" => "bar") }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
        end
      end

      context "with hash of values" do
        let(:opts) { { values: { "one" => 1, "two" => 2, "three" => 3, "bert" => "ernie" } } }

        { "one" => 1, "two" => 2, "three" => 3, "bert" => "ernie" }.each do |k, v|
          it "gives back #{v} for enum option #{k}" do
            expect(variable("MY_ENUM" => k).value).to eq(v)
          end
        end

        %w{foo bar baz}.each do |s|
          it "rejects invalid enum value #{s} with an exception" do
            expect { variable("MY_ENUM" => s) }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
          end
        end

        it "raises an exception if no variable given" do
          expect { variable("FOO" => "bar") }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
        end
      end

      context "with a default" do
        let(:opts) { { default: 42, values: %w{one two three} } }

        it "returns the default if no value given" do
          expect(variable("FOO" => "bar").value).to eq(42)
        end

        it "returns a valid value if given" do
          expect(variable("MY_ENUM" => "one").value).to eq("one")
        end

        it "raises an exception on an invalid value" do
          expect { variable("MY_ENUM" => "bob") }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
        end
      end

      context "with a sensitive variable" do
        let(:opts) { { sensitive: true, values: %w{one two three} } }

        it "redacts the variable value" do
          env = { "FOO" => "bar", "MY_ENUM" => "three" }

          with_overridden_constant Object, :ENV, env do
            expect { variable(env).redact!(env) }.to_not raise_error
            expect(env).to eq("FOO" => "bar", "MY_ENUM" => "*SENSITIVE*")
          end
        end

        context "with a default" do
          let(:opts) { { sensitive: true, default: "bob", values: [] } }

          it "does not add the variable to the environment" do
            env = { "FOO" => "bar" }

            with_overridden_constant Object, :ENV, env do
              expect { variable(env).redact!(env) }.to_not raise_error
              expect(env).to eq("FOO" => "bar")
            end
          end
        end
      end
    end
  end
end
