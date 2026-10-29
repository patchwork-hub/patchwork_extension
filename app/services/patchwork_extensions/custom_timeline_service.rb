# frozen_string_literal: true

module PatchworkExtensions
  class CustomTimelineService < ::BaseService
    include Redisable if defined?(Redisable)

    MAX_ITEMS = 400

    def timeline_key
      "feed:mix_channel_local_timeline"
    end

    def trim
      redis.zremrangebyrank(timeline_key, 0, -(MAX_ITEMS + 1))
    end

    def add_custom_public_status(status_id)
      return unless status_id

      push_to_mix_channel_local_timeline(status_id)
      trim
    end

    def remove_custom_public_status(status_id)
      return unless status_id

      unpush_from_mix_channel_local_timeline(status_id)
    end

    def push_to_mix_channel_local_timeline(status_id)
      redis.zadd(timeline_key, status_id, status_id)
    end

    def unpush_from_mix_channel_local_timeline(status_id)
      redis.zrem(timeline_key, status_id)
    end
  end
end
