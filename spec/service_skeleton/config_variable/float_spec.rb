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

  describe "#float" do
    let(:var_name) { :MY_FLOAT }

    it "accepts a variable declaration and registers it" do
      klass.float(var_name)
      expect(klass.registered_variables).to include(name: :MY_FLOAT, class: ServiceSkeleton::ConfigVariable::Float, opts: { sensitive: false, range: -Float::INFINITY..Float::INFINITY })
    end

    describe "variable object" do
      before(:each) do
        klass.float(:MY_FLOAT, **opts)
      end

      context "with no specified opts" do
        let(:opts) { {} }

        { "0" => 0, "1" => 1, "3.14159" => 3.14159, "-1.2345" => -1.2345 }.each do |s, f|
          it "returns a float for string #{s.inspect}" do
            expect(variable("MY_FLOAT" => s).value).to be_within(0.000001).of(f)
          end
        end

        %w{zero one pi ohai!}.each do |s|
          it "raises an exception for non-float string #{s.inspect}" do
            expect { variable("MY_FLOAT" => s) }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
          end
        end

        it "raises an exception if no value given" do
          expect { variable("FOO" => "bar") }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
        end
      end

      context "with a default" do
        let(:opts) { { default: 1.41421356 } }

        it "returns the default if no value given" do
          expect(variable("FOO" => "bar").value).to be_within(0.0000001).of(1.41421356)
        end

        it "parses a value if one is given" do
          expect(variable("MY_FLOAT" => "3.14159").value).to be_within(0.0000001).of(3.14159)
        end
      end

      context "with a validity range" do
        let(:opts) { { range: 0..Float::INFINITY } }

        { "0" => 0, "1" => 1, "3.14159" => 3.14159 }.each do |s, i|
          it "returns a float for valid string #{s.inspect}" do
            expect(variable("MY_FLOAT" => s).value).to eq(i)
          end
        end

        it "raises an exception for floats which are out-of-range" do
          expect { variable("MY_FLOAT" => "-1.41421356") }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
        end
      end

      context "with a sensitive variable" do
        let(:opts) { { sensitive: true } }

        it "redacts the variable value" do
          env = { "FOO" => "bar", "MY_FLOAT" => "1.2345" }

          with_overridden_constant Object, :ENV, env do
            expect { variable(env).redact!(env) }.to_not raise_error
            expect(env).to eq("FOO" => "bar", "MY_FLOAT" => "*SENSITIVE*")
          end
        end

        context "with a default" do
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
