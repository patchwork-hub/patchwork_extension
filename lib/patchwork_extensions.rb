# frozen_string_literal: true

require_relative "patchwork_extensions/version"
require_relative "patchwork_extensions/configuration"
require_relative "patchwork_extensions/engine"

module PatchworkExtensions
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
