require_relative "./spec_helper"

require "service_skeleton/filtering_logger"

describe FilteringLogger do
  let(:logger) { Logger.new("/dev/null") }
  let(:logdev) { logger.instance_variable_get(:@logdev) }

  it "accepts a filter spec" do
    expect { logger.filters = [["buggy", Logger::DEBUG], [/noisy/i, Logger::ERROR]] }.to_not raise_error
  end

  context "without a filter spec" do
    it "works normally with severity info" do
      logger.level = Logger::INFO
      expect(logdev).to receive(:write).exactly(4).times

      # Shouldn't be written due to severity constraint
      logger.debug("x") { "ohai!" }

      # Should be written
      logger.info("x") { "ohai!" }
      logger.warn("x") { "ohai!" }
      logger.error("x") { "ohai!" }
      logger.fatal("x") { "ohai!" }
    end

    it "works normally with severity debug" do
      logger.level = Logger::DEBUG
      expect(logdev).to receive(:write).exactly(5).times

      # Should be written
      logger.debug("x") { "ohai!" }
      logger.info("x") { "ohai!" }
      logger.warn("x") { "ohai!" }
      logger.error("x") { "ohai!" }
      logger.fatal("x") { "ohai!" }
    end
  end

  context "with a filter spec" do
    before :each do
      logger.filters = [["x", Logger::DEBUG], [/y/, Logger::WARN]]
      logger.level = Logger::INFO
    end

    it "writes all 'x' messages down to debug" do
      expect(logdev).to receive(:write).exactly(5).times

      # Should be written
      logger.debug("x") { "ohai!" }
      logger.info("x") { "ohai!" }
      logger.warn("x") { "ohai!" }
      logger.error("x") { "ohai!" }
      logger.fatal("x") { "ohai!" }
    end

    it "writes /y/ messages only at WARN and above" do
      expect(logdev).to receive(:write).exactly(3).times

      # Shouldn't be written due to matching /y/
      logger.debug("xyzzy") { "ohai!" }
      logger.info("xyzzy") { "ohai!" }

      # Should be written
      logger.warn("xyzzy") { "ohai!" }
      logger.error("xyzzy") { "ohai!" }
      logger.fatal("xyzzy") { "ohai!" }
    end

    it "writes non-matching messages at INFO and above" do
      expect(logdev).to receive(:write).exactly(4).times

      # Shouldn't be written due to default level
      logger.debug("abc") { "ohai!" }

      # Should be written
      logger.info("abc") { "ohai!" }
      logger.warn("abc") { "ohai!" }
      logger.error("abc") { "ohai!" }
      logger.fatal("abc") { "ohai!" }
    end
  end

  context "with an overlapping filter spec" do
    before :each do
      logger.filters = [[/xyz/, Logger::DEBUG], [/y/, Logger::WARN]]
      logger.level = Logger::INFO
    end

    it "prefers the /xyz/ match" do
      expect(logdev).to receive(:write).exactly(3).times

      # Should be written
      logger.debug("xyzzy") { "ohai!" }
      logger.warn("why") { "ohai!" }
      logger.info("abc") { "ohai!" }

      # Shouldn't be written
      logger.info("why") { "ohai!" }
      logger.debug("abc") { "ohai!" }
    end
  end
end
