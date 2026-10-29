# frozen_string_literal: true

require "rails"
require "action_controller/railtie"

require "patchwork_extensions"

module Dummy
  class Application < Rails::Application
    config.load_defaults 7.0
    config.eager_load = false
    config.secret_key_base = "patchwork-extensions-dummy-test-key"
    config.logger = Logger.new(nil)
    config.hosts.clear
  end
end
