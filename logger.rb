require 'logger'

module Fawn
  def logger
    @logger ||= Logger.new(STDOUT).tap do |logger|
      logger.level = Logger::WARN
    end
  end
end
