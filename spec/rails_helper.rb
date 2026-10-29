# frozen_string_literal: true

require "spec_helper"

ENV["RAILS_ENV"] ||= "test"

# Support two boot modes:
#
#   1. Standalone — default when running `bundle exec rspec` from the gem root.
#      Boots the minimal dummy Rails app. Host-dependent specs (anything hitting
#      Mastodon's Api::BaseController, Doorkeeper, Fabrication) are skipped via
#      `require_host!`.
#
#   2. Host-app mode — set MASTODON_ROOT (and BUNDLE_GEMFILE) to a Mastodon
#      checkout. Boots the full Mastodon environment so request specs exercise
#      real authentication and authorization.

unless defined?(MASTODON_ROOT)
  MASTODON_ROOT = ENV["MASTODON_ROOT"].to_s
end

host_environment_path = File.join(MASTODON_ROOT, "config", "environment.rb")

if !MASTODON_ROOT.empty? && File.exist?(host_environment_path)
  # Do NOT require "patchwork_extensions" manually here: the gem is in the
  # host's Gemfile, so the host boot's Bundler.require loads it after
  # ActiveSupport is available. Requiring it early breaks Rails::Engine
  # (rails/initializable needs ActiveSupport core extensions).
  require host_environment_path
  HOST_ENVIRONMENT_LOADED = true

  # The host's spec_helper wires Chewy (:bypass strategy), database seeds and
  # registration-mode defaults that Mastodon factories depend on.
  host_spec_helper = File.join(MASTODON_ROOT, "spec", "spec_helper.rb")
  require host_spec_helper if File.exist?(host_spec_helper)
else
  require File.expand_path("dummy/config/environment", __dir__)
  HOST_ENVIRONMENT_LOADED = false
end

abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"

# Minimal Mastodon class stubs for standalone mode; no-ops in host mode.
require File.expand_path("support/mastodon_stubs", __dir__)

# Skip helper for specs that need the real Mastodon host (OAuth, Fabrication,
# Mastodon controllers). In standalone mode these specs are skipped.
def require_host!
  skip "Requires the Mastodon host harness (set MASTODON_ROOT to the host app)." unless HOST_ENVIRONMENT_LOADED
end

RSpec.configure do |config|
  config.use_active_record = false unless defined?(ActiveRecord)

  # Match the host's rails_helper: wrap each example in a transaction that is
  # rolled back, so fabricated data never persists between runs. Without this,
  # host-mode runs leave residue that collides with Faker's deterministic
  # per-seed values on subsequent runs.
  config.use_transactional_fixtures = true if defined?(ActiveRecord)
end
