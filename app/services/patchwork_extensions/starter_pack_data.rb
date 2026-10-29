# frozen_string_literal: true

require "json"
require "pathname"
require "active_support/core_ext/numeric/time"
require "active_support/core_ext/object/blank"

module PatchworkExtensions
  # COMMUNITY-03: Reads packaged starter-pack JSON with a Redis-backed cache
  # validated against file modification time. Behavior mirrors the loader that
  # was embedded in NewsmastMastodon::Api::V1::ChannelsController, including
  # the Redis key format, so cached entries remain compatible at cutover.
  class StarterPackData
    CACHE_TTL = 24.hours

    def initialize(redis:, data_root:)
      @redis = redis
      @data_root = Pathname.new(data_root)
    end

    # Returns the parsed JSON array for +relative_path+ (e.g.
    # "twt/starter_pack_list.json"), or [] when the file does not exist.
    def load(relative_path, namespace:)
      full_path = @data_root.join(relative_path)
      return [] unless File.exist?(full_path)

      file_mtime = File.mtime(full_path).to_i
      cache_key = self.class.cache_key(namespace: namespace, relative_path: relative_path)

      cached = @redis.get(cache_key)
      if cached.present?
        parsed_cache = JSON.parse(cached)
        return parsed_cache["data"] if parsed_cache["mtime"] == file_mtime
      end

      data = JSON.parse(File.read(full_path))
      @redis.set(cache_key, { mtime: file_mtime, data: data }.to_json, ex: CACHE_TTL.to_i)
      data
    end

    def self.cache_key(namespace:, relative_path:)
      "accounts:starter_pack_#{namespace}_#{relative_path.gsub('/', '_').gsub('.json', '')}"
    end
  end
end
