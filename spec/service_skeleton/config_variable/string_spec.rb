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

  describe "#string" do
    let(:var_name) { :MY_STRING }

    it "accepts a variable declaration and registers it" do
      klass.string(var_name)
      expect(klass.registered_variables).to include(name: :MY_STRING, class: ServiceSkeleton::ConfigVariable::String, opts: { sensitive: false, match: nil })
    end

    describe "variable object" do
      before(:each) do
        klass.string(var_name, **opts)
      end

      context "with no specified opts" do
        let(:opts) { {} }

        it "accepts a string" do
          expect(variable("MY_STRING" => "ohai!").value).to eq("ohai!")
        end

        it "raises an exception during initialization if no value given" do
          expect { variable("FOO" => "bar") }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
        end

        it "does not redact" do
          env = { "FOO" => "bar", "MY_STRING" => "ohai!" }

          with_overridden_constant Object, :ENV, env do
            expect { variable(env).redact!(env) }.to_not raise_error
            expect(env).to eq("FOO" => "bar", "MY_STRING" => "ohai!")
          end
        end
      end

      context "with a default" do
        let(:opts) { { default: "lolrus" } }

        it "returns the default if no value given" do
          expect(variable("FOO" => "bar").value).to eq("lolrus")
        end

        it "returns the value given if given one" do
          expect(variable("MY_STRING" => "hi there").value).to eq("hi there")
        end
      end

      context "with a sensitive variable" do
        let(:opts) { { sensitive: true } }

        it "redacts the variable value" do
          env = { "FOO" => "bar", "MY_STRING" => "s3kr1t" }

          with_overridden_constant Object, :ENV, env do
            expect { variable(env).redact!(env) }.to_not raise_error
            expect(env).to eq("FOO" => "bar", "MY_STRING" => "*SENSITIVE*")
          end
        end

        context "and a default" do
          let(:opts) { { sensitive: true, default: "hey" } }

          it "does not add the variable to the environment" do
            env = { "FOO" => "bar" }

            with_overridden_constant Object, :ENV, env do
              expect { variable(env).redact!(env) }.to_not raise_error
              expect(env).to eq("FOO" => "bar")
            end
          end
        end
      end

      context "with a match" do
        let(:opts) { { match: /foo/, default: "nah" } }

        it "accepts a value that matches" do
          expect(variable("MY_STRING" => "boofoobloo").value).to eq("boofoobloo")
        end

        it "does not accept a value that doesn't match" do
          expect { variable("MY_STRING" => "barharhar") }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
        end

        it "is OK with a default that doesn't match" do
          expect(variable("SOMETHING" => "funny").value).to eq("nah")
        end
      end
    end
  end
end
