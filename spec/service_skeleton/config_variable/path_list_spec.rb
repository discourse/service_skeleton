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

  describe "path_list" do
    let(:var_name) { :MY_PATH_LIST }

    it "accepts a variable declaration and registers it" do
      klass.path_list(var_name)
      expect(klass.registered_variables).to include(name: :MY_PATH_LIST, class: ServiceSkeleton::ConfigVariable::PathList, opts: { sensitive: false })
    end

    describe "variable object" do
      before(:each) do
        klass.path_list(:MY_PATH_LIST, **opts)
      end

      context "with no specified opts" do
        let(:opts) { {} }

        { "" => [], "/foo/bar" => ["/foo/bar"], "/x:/y" => ["/x", "/y"] }.each do |s, v|
          it "returns an array for string #{s.inspect}" do
            expect(variable("MY_PATH_LIST" => s).value).to eq(v)
          end
        end

        it "raises an exception if no value given" do
          expect { variable("FOO" => "bar") }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
        end
      end

      context "with a default" do
        let(:opts) { { default: [] } }

        it "returns the default if no value given" do
          expect(variable("FOO" => "bar").value).to eq([])
        end

        it "parses a value if one is given" do
          expect(variable("MY_PATH_LIST" => "/xyzzy").value).to eq(["/xyzzy"])
        end
      end

      context "with a sensitive variable" do
        let(:opts) { { sensitive: true } }

        it "redacts the variable value" do
          env = { "FOO" => "bar", "MY_PATH_LIST" => "/secret/path" }

          with_overridden_constant Object, :ENV, env do
            expect { variable(env).redact!(env) }.to_not raise_error
            expect(env).to eq("FOO" => "bar", "MY_PATH_LIST" => "*SENSITIVE*")
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
