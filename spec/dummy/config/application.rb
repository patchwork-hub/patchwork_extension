# frozen_string_literal: true

require "rails"
require "action_controller/railtie"
# AUTH-04 services and controllers use ActiveModel::Type::Boolean for ENV flag
# casting; the dummy app must load ActiveModel for standalone specs.
require "active_model/railtie"

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
