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

  describe "url" do
    let(:var_name) { :MY_URL }

    it "accepts a variable declaration and registers it" do
      klass.url(var_name)
      expect(klass.registered_variables).to include(name: :MY_URL, class: ServiceSkeleton::ConfigVariable::URL, opts: { sensitive: false })
    end

    describe "variable object" do
      before(:each) do
        klass.url(:MY_URL, **opts)
      end

      context "with no specified opts" do
        let(:opts) { {} }

        it "returns a valid URL" do
          expect(variable("MY_URL" => "https://example.com").value).to eq("https://example.com")
        end

        it "raises an exception on an invalid URL" do
          expect { variable("MY_URL" => "flibbety gibbets") }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
        end

        it "raises an exception if no variable given" do
          expect { variable("FOO" => "bar") }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
        end

        context "with a password in the URL" do
          let(:env) { { "MY_URL" => "https://bob:s3kr1t@example.com" } }

          it "qualifies the variable for redaction" do
            expect(variable(env).redact?(env)).to be(true)
          end

          it "auto-redacts just the password" do
            with_overridden_constant Object, :ENV, env do
              var = variable(env)

              expect(var.value).to eq("https://bob:s3kr1t@example.com")
              var.redact!(env)
              expect(env).to eq("MY_URL" => "https://bob:*REDACTED*@example.com")
            end
          end
        end
      end

      context "with a default" do
        let(:opts) { { default: "http://default.example.com" } }

        it "returns the default if no value given" do
          expect(variable("FOO" => "bar").value).to eq("http://default.example.com")
        end

        it "returns a valid value if given" do
          expect(variable("MY_URL" => "https://example.com").value).to eq("https://example.com")
        end
      end

      context "with a sensitive variable" do
        let(:opts) { { sensitive: true } }

        it "qualifies for redaction" do
          env = { "MY_URL" => "http://example.com" }

          expect(variable(env).redact?(env)).to be(true)
        end

        it "redacts the whole variable value" do
          env = { "FOO" => "bar", "MY_URL" => "http://example.com" }

          with_overridden_constant Object, :ENV, env do
            expect { variable(env).redact!(env) }.to_not raise_error
            expect(env).to eq("FOO" => "bar", "MY_URL" => "*SENSITIVE*")
          end
        end

        context "and a default" do
          let(:opts) { { sensitive: true, default: "http://default.example.com" } }

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
