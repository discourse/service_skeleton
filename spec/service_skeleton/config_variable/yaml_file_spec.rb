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

  describe "yaml_file" do
    let(:var_name) { :MY_YAML_FILE }

    it "accepts a variable declaration and registers it" do
      klass.yaml_file(var_name)
      expect(klass.registered_variables)
        .to include(
              name: :MY_YAML_FILE,
              class: ServiceSkeleton::ConfigVariable::YamlFile,
              opts: { sensitive: false, klass: nil })
    end

    describe "variable object" do
      before(:each) do
        klass.yaml_file(:MY_YAML_FILE, **opts)
        allow(File).to receive(:read).and_return("default value")
      end

      context "with no specified opts" do
        let(:opts) { {} }

        it "raises an exception if no value given" do
          expect { variable("FOO" => "bar") }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
        end

        it "raises an exception if the file doesn't exist" do
          expect(File).to receive(:read).with("/some/file").and_raise(Errno::ENOENT)
          expect { variable("MY_YAML_FILE" => "/some/file") }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
        end

        it "raises an exception if the file isn't readable" do
          expect(File).to receive(:read).with("/some/file").and_raise(Errno::EPERM)
          expect { variable("MY_YAML_FILE" => "/some/file") }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
        end

        it "raises an exception if the file isn't valid YAML" do
          expect(File).to receive(:read).with("/some/file").and_return("bob: one: two: three")
          expect { variable("MY_YAML_FILE" => "/some/file") }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
        end

        it "returns the deserialized file contents" do
          expect(File).to receive(:read).with("/some/file").and_return("- one\n- two\n- three\n")
          expect(variable("MY_YAML_FILE" => "/some/file").value).to eq(%w{one two three})
        end
      end

      context "with a default" do
        let(:opts) { { default: [] } }

        it "returns the default if no value given" do
          expect(variable("FOO" => "bar").value).to eq([])
        end

        it "parses the file if one is given" do
          expect(File).to receive(:read).with("/some/file").and_return("- one\n- two\n- three\n")
          expect(variable("MY_YAML_FILE" => "/some/file").value).to eq(%w{one two three})
        end
      end

      context "with a sensitive variable" do
        let(:opts) { { sensitive: true } }

        it "redacts the variable value" do
          env = { "FOO" => "bar", "MY_YAML_FILE" => "/secret/file" }
          allow(File).to receive(:world_readable?).and_return(nil)

          with_overridden_constant Object, :ENV, env do
            expect { variable(env).redact!(env) }.to_not raise_error
            expect(env).to eq("FOO" => "bar", "MY_YAML_FILE" => "*SENSITIVE*")
          end
        end

        it "raises an error if the file is world-readable" do
          env = { "FOO" => "bar", "MY_YAML_FILE" => "/secret/file" }
          expect(File).to receive(:world_readable?).with("/secret/file").and_return(511)

          expect { variable(env).redact!(env) }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
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

      context "with a klass" do
        let(:value_class) { Class.new.tap { |k| k.define_method(:initialize) { |*_| } } }
        let(:opts)        { { klass: value_class } }

        it "instantiates the given class with the file contents" do
          expect(File).to receive(:read).with("/some/file").and_return("one: two\n")
          expect(value_class).to receive(:new).with({ "one" => "two" }).and_call_original
          expect(variable("MY_YAML_FILE" => "/some/file").value).to be_a(value_class)
        end

        context "with a default" do
          let(:opts) { { klass: value_class, default: "bob" } }

          it "does not instantiate the class" do
            expect(value_class).to_not receive(:new)

            expect(variable("FOO" => "bar").value).to eq("bob")
          end
        end
      end
    end
  end
end
