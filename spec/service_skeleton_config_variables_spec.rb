require_relative "./spec_helper"

require "service_skeleton/config_variables"

describe ServiceSkeleton::ConfigVariables do
  let(:klass) { Class.new.extend(ServiceSkeleton::ConfigVariables) }

  def variable(var)
    klass
      .registered_variables
      .find { |r| r.name == var }
  end

  describe "#register_variable" do
    it "inserts the variable registration into the variable registry" do
      klass.register_variable(:XYZZY) { |v| nil }

      expect(klass.registered_variables).to match([instance_of(ServiceSkeleton::ConfigVariable)])
    end
  end

  describe "#string" do
    let(:opts) { {} }
    let(:var) { variable(:MY_STRING) }

    before(:each) do
      klass.string(:MY_STRING, **opts)
    end

    it "accepts a variable declaration and registers it" do
      expect(klass.registered_variables).to match([instance_of(ServiceSkeleton::ConfigVariable)])
    end

    it "accepts a string" do
      expect(var.value("ohai!")).to eq("ohai!")
    end

    it "raises an exception if no value given" do
      expect { var.value(nil) }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
    end

    context "with a default" do
      let(:opts) { { default: "lolrus" } }

      it "returns the default if no value given" do
        expect(var.value(nil)).to eq("lolrus")
      end

      it "returns the value given if given one" do
        expect(var.value("hi there")).to eq("hi there")
      end
    end

    context "with a sensitive variable" do
      let(:opts) { { sensitive: true } }

      it "adds the variable to the list" do
        expect(klass.registered_variables).to match([instance_of(ServiceSkeleton::ConfigVariable)])
      end

      it "marks the variable as sensitive" do
        expect(klass.registered_variables.first.sensitive?).to eq(true)
      end
    end
  end

  describe "#boolean" do
    let(:opts) { {} }
    let(:var) { variable(:MY_BOOL) }

    before(:each) do
      klass.boolean(:MY_BOOL, **opts)
    end

    it "accepts a variable declaration and registers it" do
      expect(klass.registered_variables).to match([instance_of(ServiceSkeleton::ConfigVariable)])
    end

    %w{yes YeS y on oN 1 TRUE true}.each do |s|
      it "returns true for true-ish string #{s.inspect}" do
        expect(var.value(s)).to eq(true)
      end
    end

    %w{no No n off oFf 0 false FaLsE}.each do |s|
      it "returns false for false-ish string #{s.inspect}" do
        expect(var.value(s)).to eq(false)
      end
    end

    %w{foo bar LOUD NOISES baz wombat 42}.each do |s|
      it "raises an exception when given non-boolean string #{s.inspect}" do
        expect { var.value(s) }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
      end
    end

    it "raises an exception if no value given" do
      expect { var.value(nil) }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
    end

    context "with a default" do
      let(:opts) { { default: true } }

      it "returns the default if no value given" do
        expect(var.value(nil)).to eq(true)
      end

      it "parses a value if one is given" do
        expect(var.value("true")).to eq(true)
      end
    end

    context "with a sensitive variable" do
      let(:opts) { { sensitive: true } }

      it "adds the variable to the list" do
        expect(klass.registered_variables).to match([instance_of(ServiceSkeleton::ConfigVariable)])
      end

      it "marks the variable as sensitive" do
        expect(klass.registered_variables.first.sensitive?).to eq(true)
      end
    end
  end

  describe "#integer" do
    let(:opts) { {} }
    let(:var) { variable(:MY_INT) }

    before(:each) do
      klass.integer(:MY_INT, **opts)
    end

    it "accepts a variable declaration and registers it" do
      expect(klass.registered_variables).to match([instance_of(ServiceSkeleton::ConfigVariable)])
    end

    { "0" => 0, "1" => 1, "1000" => 1000, "-42" => -42 }.each do |s, i|
      it "returns an integer for string #{s.inspect}" do
        expect(var.value(s)).to eq(i)
      end
    end

    %w{zero one ohai! 3.14159625}.each do |s|
      it "raises an exception for non-integer string #{s.inspect}" do
        expect { var.value(s) }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
      end
    end

    it "raises an exception if no value given" do
      expect { var.value(nil) }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
    end

    context "with a default" do
      let(:opts) { { default: 71 } }

      it "returns the default if no value given" do
        expect(var.value(nil)).to eq(71)
      end

      it "parses a value if one is given" do
        expect(var.value("42")).to eq(42)
      end
    end

    context "with a validity range" do
      let(:opts) { { range: 0..Float::INFINITY } }

      { "0" => 0, "1" => 1, "1000" => 1000 }.each do |s, i|
        it "returns an integer for valid string #{s.inspect}" do
          expect(var.value(s)).to eq(i)
        end
      end

      it "raises an exception for integers which are out-of-range" do
        expect { var.value("-42") }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
      end
    end

    context "with a sensitive variable" do
      let(:opts) { { sensitive: true } }

      it "adds the variable to the list" do
        expect(klass.registered_variables).to match([instance_of(ServiceSkeleton::ConfigVariable)])
      end

      it "marks the variable as sensitive" do
        expect(klass.registered_variables.first.sensitive?).to eq(true)
      end
    end
  end

  describe "#float" do
    let(:opts) { {} }
    let(:var) { variable(:MY_FLOAT) }

    before(:each) do
      klass.float(:MY_FLOAT, **opts)
    end

    it "accepts a variable declaration and registers it" do
      expect(klass.registered_variables).to match([instance_of(ServiceSkeleton::ConfigVariable)])
    end

    { "0" => 0, "1" => 1, "3.14159" => 3.14159, "-1.2345" => -1.2345 }.each do |s, f|
      it "returns a float for string #{s.inspect}" do
        expect(var.value(s)).to be_within(0.000001).of(f)
      end
    end

    %w{zero one pi ohai!}.each do |s|
      it "raises an exception for non-integer string #{s.inspect}" do
        expect { var.value(s) }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
      end
    end

    it "raises an exception if no value given" do
      expect { var.value(nil) }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
    end

    context "with a default" do
      let(:opts) { { default: 1.41421356 } }

      it "returns the default if no value given" do
        expect(var.value(nil)).to be_within(0.0000001).of(1.41421356)
      end

      it "parses a value if one is given" do
        expect(var.value("3.14159")).to be_within(0.0000001).of(3.14159)
      end
    end

    context "with a validity range" do
      let(:opts) { { range: 0..Float::INFINITY } }

      { "0" => 0, "1" => 1, "3.14159" => 3.14159 }.each do |s, i|
        it "returns a float for valid string #{s.inspect}" do
          expect(var.value(s)).to eq(i)
        end
      end

      it "raises an exception for floats which are out-of-range" do
        expect { var.value("-1.41421356") }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
      end
    end

    context "with a sensitive variable" do
      let(:opts) { { sensitive: true } }

      it "adds the variable to the list" do
        expect(klass.registered_variables).to match([instance_of(ServiceSkeleton::ConfigVariable)])
      end

      it "marks the variable as sensitive" do
        expect(klass.registered_variables.first.sensitive?).to eq(true)
      end
    end
  end
end
