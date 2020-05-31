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

  describe "#integer" do
    let(:opts) { {} }
    let(:var_name) { :MY_INT }

    it "accepts a variable declaration and registers it" do
      klass.integer(var_name)
      expect(klass.registered_variables).to include(name: :MY_INT, class: ServiceSkeleton::ConfigVariable::Integer, opts: { sensitive: false, range: -Float::INFINITY..Float::INFINITY })
    end

    describe "variable object" do
      before(:each) do
        klass.integer(:MY_INT, **opts)
      end

      context "with no specified opts" do
        let(:opts) { {} }

        { "0" => 0, "1" => 1, "1000" => 1000, "-42" => -42 }.each do |s, i|
          it "returns an integer for string #{s.inspect}" do
            expect(variable("MY_INT" => s).value).to eq(i)
          end
        end

        %w{zero one ohai! 3.14159625}.each do |s|
          it "raises an exception for non-integer string #{s.inspect}" do
            expect { variable("MY_INT" => s) }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
          end
        end

        it "raises an exception if no value given" do
          expect { variable("FOO" => "bar") }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
        end

        it "does not redact" do
          env = { "FOO" => "bar", "MY_INT" => "42" }

          with_overridden_constant Object, :ENV, env do
            expect { variable(env).redact!(env) }.to_not raise_error
            expect(env).to eq("FOO" => "bar", "MY_INT" => "42")
          end
        end
      end

      context "with a default" do
        let(:opts) { { default: 71 } }

        it "returns the default if no value given" do
          expect(variable("FOO" => "bar").value).to eq(71)
        end

        it "parses a value if one is given" do
          expect(variable("MY_INT" => "42").value).to eq(42)
        end
      end

      context "with a validity range" do
        let(:opts) { { range: 0..Float::INFINITY } }

        { "0" => 0, "1" => 1, "1000" => 1000 }.each do |s, i|
          it "returns an integer for valid string #{s.inspect}" do
            expect(variable("MY_INT" => s).value).to eq(i)
          end
        end

        it "raises an exception for integers which are out-of-range" do
          expect { variable("MY_INT" => "-42") }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
        end
      end

      context "with a sensitive variable" do
        let(:opts) { { sensitive: true } }

        it "redacts the variable value" do
          env = { "FOO" => "bar", "MY_INT" => "42" }

          with_overridden_constant Object, :ENV, env do
            expect { variable(env).redact!(env) }.to_not raise_error
            expect(env).to eq("FOO" => "bar", "MY_INT" => "*SENSITIVE*")
          end
        end

        context "and a default" do
          let(:opts) { { sensitive: true, default: true } }

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
