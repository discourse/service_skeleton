# frozen_string_literal: true

require_relative "./spec_helper"

require "service_skeleton/config_variables"

describe ServiceSkeleton::ConfigVariables do
  let(:klass) { Class.new.extend(ServiceSkeleton::ConfigVariables) }

  def variable(env)
    rego = klass
      .registered_variables
      .find { |r| r[:name] == var_name }
    rego[:class].new(rego[:name], env, **rego[:opts])
  end

  describe "#register_variable" do
    it "inserts a simple variable registration into the variable registry" do
      klass.register_variable(:XYZZY, ServiceSkeleton::ConfigVariable::String)

      expect(klass.registered_variables).to eq([name: :XYZZY, class: ServiceSkeleton::ConfigVariable::String, opts: {}])
    end

    it "inserts a default-value variable registration into the variable registry" do
      klass.register_variable(:XYZZY, ServiceSkeleton::ConfigVariable::String, default: "42")

      expect(klass.registered_variables).to eq([name: :XYZZY, class: ServiceSkeleton::ConfigVariable::String, opts: { default: "42" }])
    end

    it "inserts an arbitrary-opts variable registration into the variable registry" do
      klass.register_variable(:XYZZY, ServiceSkeleton::ConfigVariable::String, something: "funny")

      expect(klass.registered_variables).to eq([name: :XYZZY, class: ServiceSkeleton::ConfigVariable::String, opts: { something: "funny" }])
    end
  end

  describe "#string" do
    let(:var_name) { :MY_STRING }

    it "accepts a variable declaration and registers it" do
      klass.string(var_name)
      expect(klass.registered_variables).to eq([{ name: :MY_STRING, class: ServiceSkeleton::ConfigVariable::String, opts: { sensitive: false } }])
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
    end
  end

  describe "#boolean" do
    let(:var_name) { :MY_BOOL }

    it "accepts a variable declaration and registers it" do
      klass.boolean(var_name)
      expect(klass.registered_variables).to eq([{ name: :MY_BOOL, class: ServiceSkeleton::ConfigVariable::Boolean, opts: { sensitive: false } }])
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

  describe "#integer" do
    let(:opts) { {} }
    let(:var_name) { :MY_INT }

    it "accepts a variable declaration and registers it" do
      klass.integer(var_name)
      expect(klass.registered_variables).to eq([{ name: :MY_INT, class: ServiceSkeleton::ConfigVariable::Integer, opts: { sensitive: false, range: -Float::INFINITY..Float::INFINITY } }])
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

  describe "#float" do
    let(:var_name) { :MY_FLOAT }

    it "accepts a variable declaration and registers it" do
      klass.float(var_name)
      expect(klass.registered_variables).to eq([{ name: :MY_FLOAT, class: ServiceSkeleton::ConfigVariable::Float, opts: { sensitive: false, range: -Float::INFINITY..Float::INFINITY } }])
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

  describe "path_list" do
    let(:var_name) { :MY_PATH_LIST }

    it "accepts a variable declaration and registers it" do
      klass.path_list(var_name)
      expect(klass.registered_variables).to eq([{ name: :MY_PATH_LIST, class: ServiceSkeleton::ConfigVariable::PathList, opts: { sensitive: false } }])
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

  describe "kv_list" do
    let(:var_name) { :MY_KV_LIST }

    it "accepts a variable declaration and registers it" do
      klass.kv_list(var_name)
      expect(klass.registered_variables).to eq([{ name: :MY_KV_LIST, class: ServiceSkeleton::ConfigVariable::KVList, opts: { sensitive: false, key_pattern: /\AMY_KV_LIST_(.*)\z/ } }])
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
      expect(klass.registered_variables).to eq([{ name: :MY_ENUM, class: ServiceSkeleton::ConfigVariable::Enum, opts: { sensitive: false, values: ["one", "two", "three"] } }])
    end

    it "accepts a hash of string => object pairs" do
      klass.enum(var_name, values: { "one" => 1, "two" => 2, "three" => 3 })
      expect(klass.registered_variables).to eq([{ name: :MY_ENUM, class: ServiceSkeleton::ConfigVariable::Enum, opts: { sensitive: false, values: { "one" => 1, "two" => 2, "three" => 3 } } }])
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

        context "and a default" do
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

  describe "url" do
    let(:var_name) { :MY_URL }

    it "accepts a variable declaration and registers it" do
      klass.url(var_name)
      expect(klass.registered_variables).to eq([{ name: :MY_URL, class: ServiceSkeleton::ConfigVariable::URL, opts: { sensitive: false } }])
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

        it "auto-redacts passwords in the URL" do
          env = { "MY_URL" => "https://bob:s3kr1t@example.com" }

          with_overridden_constant Object, :ENV, env do
            var = variable(env)

            expect(var.value).to eq("https://bob:s3kr1t@example.com")
            expect(var.redact?(env)).to be(true)
            var.redact!(env)
            expect(env).to eq("MY_URL" => "https://bob:*REDACTED*@example.com")
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
