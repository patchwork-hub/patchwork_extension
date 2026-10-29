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
