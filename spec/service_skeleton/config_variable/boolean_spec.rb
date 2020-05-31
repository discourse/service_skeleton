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

  describe "#boolean" do
    let(:var_name) { :MY_BOOL }

    it "accepts a variable declaration and registers it" do
      klass.boolean(var_name)
      expect(klass.registered_variables).to include(name: :MY_BOOL, class: ServiceSkeleton::ConfigVariable::Boolean, opts: { sensitive: false })
    end

    describe "variable object" do
      before(:each) do
        klass.boolean(var_name, **opts)
      end

      context "with no specified opts" do
        let(:opts) { {} }

        %w{yes YeS y on oN 1 TRUE true}.each do |s|
          it "returns true for true-ish string #{s.inspect}" do
            expect(variable("MY_BOOL" => s).value).to eq(true)
          end
        end

        %w{no No n off oFf 0 false FaLsE}.each do |s|
          it "returns false for false-ish string #{s.inspect}" do
            expect(variable("MY_BOOL" => s).value).to eq(false)
          end
        end

        %w{foo bar LOUD NOISES baz wombat 42}.each do |s|
          it "raises an exception when given non-boolean string #{s.inspect}" do
            expect { variable("MY_BOOL" => s) }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
          end
        end

        it "raises an exception if no value given" do
          expect { variable("FOO" => "bar") }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
        end

        it "does not redact" do
          env = { "FOO" => "bar", "MY_BOOL" => "yes" }

          with_overridden_constant Object, :ENV, env do
            expect { variable(env).redact!(env) }.to_not raise_error
            expect(env).to eq("FOO" => "bar", "MY_BOOL" => "yes")
          end
        end
      end

      context "with a default" do
        let(:opts) { { default: true } }

        it "returns the default if no value given" do
          expect(variable("FOO" => "bar").value).to eq(true)
        end

        it "parses a value if one is given" do
          expect(variable("MY_BOOL" => "true").value).to eq(true)
        end
      end

      context "with a sensitive variable" do
        let(:opts) { { sensitive: true } }

        it "redacts the variable value" do
          env = { "FOO" => "bar", "MY_BOOL" => "true" }

          with_overridden_constant Object, :ENV, env do
            expect { variable(env).redact!(env) }.to_not raise_error
            expect(env).to eq("FOO" => "bar", "MY_BOOL" => "*SENSITIVE*")
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
