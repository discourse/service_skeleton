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

  describe "kv_list" do
    let(:var_name) { :MY_KV_LIST }

    it "accepts a variable declaration and registers it" do
      klass.kv_list(var_name)
      expect(klass.registered_variables).to include(name: :MY_KV_LIST, class: ServiceSkeleton::ConfigVariable::KVList, opts: { sensitive: false, key_pattern: /\AMY_KV_LIST_(.*)\z/ })
    end

    describe "variable object" do
      before(:each) do
        klass.kv_list(:MY_KV_LIST, **opts)
      end

      context "with no specified opts" do
        let(:opts) { {} }

        it "raises an exception if no variable names match" do
          expect { variable("FOO" => "bar") }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
        end

        it "picks out relevant records" do
          expect(variable(
            "FOO" => "bar",
            "MY_KV_LIST_x" => "y",
            "MY_KV_LIST_baz" => "wombat",
          ).value).to eq(x: "y", baz: "wombat")
        end
      end

      context "with a default" do
        let(:opts) { { default: { a: "42" } } }

        it "returns the default if no value given" do
          expect(variable("FOO" => "bar").value).to eq(a: "42")
        end

        it "plucks the keys if they're given" do
          expect(variable(
            "FOO" => "bar",
            "MY_KV_LIST_x" => "y",
          ).value).to eq(x: "y")
        end
      end

      context "with a custom key_pattern" do
        let(:opts) { { key_pattern: /\AOVER_HERE_(.*)\z/ } }

        it "only plucks the keys that match the key pattern" do
          expect(variable(
            "FOO" => "bar",
            "MY_KV_LIST_x" => "y",
            "OVER_HERE_bob" => "fred",
          ).value).to eq(bob: "fred")
        end
      end

      context "with a sensitive variable" do
        let(:opts) { { sensitive: true } }

        it "redacts keys that match the key pattern" do
          env = { "FOO" => "bar", "MY_KV_LIST_secret" => "s3kr1t" }

          with_overridden_constant Object, :ENV, env do
            expect { variable(env).redact!(env) }.to_not raise_error
            expect(env).to eq("FOO" => "bar", "MY_KV_LIST_secret" => "*SENSITIVE*")
          end
        end
      end
    end
  end
end
