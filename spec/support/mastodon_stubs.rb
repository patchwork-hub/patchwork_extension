# frozen_string_literal: true

# Minimal Mastodon class stubs so gem code can be *loaded* in standalone mode
# (dummy app), where the host application classes do not exist. Each stub is
# guarded, so in host mode the real Mastodon classes win. Host-dependent
# behavior is still skipped via `require_host!` in the specs themselves.

# BaseService – base class for Mastodon service objects
unless defined?(BaseService)
  class BaseService
    def call(*); end
  end
end

# Redisable – minimal fallback for standalone gem tests. Host-mode specs use the
# real Mastodon implementation, while standalone specs only need the mixin to be
# defined so extracted classes can load without a host application.
unless defined?(Redisable)
  module Redisable
    def redis
      @redis ||= Redis.new
    end
  end
end

# RoutingHelper – URL helpers mixin included by AfterUploadImageService
# (MEDIA-01). Only needs to exist so the service class can load standalone.
unless defined?(RoutingHelper)
  module RoutingHelper
    def full_asset_url(*); end
  end
end

# Sidekiq::Worker – minimal fallback so Gem B workers (MEDIA-01) can load
# standalone. Sidekiq itself is provided at runtime by the host Mastodon app.
unless defined?(Sidekiq::Worker)
  module Sidekiq
    module Worker
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def sidekiq_options(*); end
        def perform_async(*); end
      end
    end
  end
end
