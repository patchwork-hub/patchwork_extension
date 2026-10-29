# frozen_string_literal: true

module PatchworkExtensions
  class ForYouFeed
    include Redisable if defined?(Redisable)

    def initialize(account, options = {})
      @account = account
      @options = options
    end

    def get(limit, max_id = nil, since_id = nil, min_id = nil)
      @status = custom_scope

      without_reblogs_scope

      without_replies_scope          if exclude_replies?
      exclude_direct_statuses_scope  if exclude_direct_statuses?

      if grouped_admin_statuses?
        grouped_admin_statuses_scope
        grouped_admin_reblogged_statuses_scope
      end

      @status.to_a_paginated_by_id(limit, max_id: max_id, since_id: since_id, min_id: min_id)
    end

    private

    attr_reader :account, :options

    def exclude_replies?
      options[:exclude_replies]
    end

    def exclude_direct_statuses?
      options[:exclude_direct_statuses]
    end

    def custom_scope
      home_status_ids   = redis.zrange(FeedManager.instance.key(:home, @account.id), 0, -1)
      mix_status_ids    = redis.zrange("feed:mix_channel_local_timeline", 0, -1)
      merged_status_ids = home_status_ids + mix_status_ids
      @status = Status.where(id: merged_status_ids).joins(:account).merge(Account.without_suspended.without_silenced)
    end

    def without_replies_scope
      @status = @status.without_replies
    end

    def without_reblogs_scope
      @status = @status.without_reblogs
    end

    def exclude_direct_statuses_scope
      @status = @status.where(visibility: %i[public unlisted])
    end

    def grouped_admin_statuses?
      options[:grouped_admin_statuses] && Status.column_names.include?("local_only")
    end

    def grouped_admin_statuses_scope
      grouped_admin_account_ids = fetch_grouped_admin_account_ids
      @status = @status.where.not(account_id: grouped_admin_account_ids)
    end

    def grouped_admin_reblogged_statuses_scope
      grouped_admin_account_ids = fetch_grouped_admin_account_ids
      return if grouped_admin_account_ids.empty?

      grouped_admin_reblogged_ids = Status
        .where(account_id: grouped_admin_account_ids)
        .where.not(reblog_of_id: nil)
        .select(:reblog_of_id)

      @status = @status.where.not(id: grouped_admin_reblogged_ids)
    end

    def fetch_grouped_admin_account_ids
      Rails.cache.fetch("grouped_admin_account_ids", expires_in: 1.hour) do
        NewsmastMastodon::CommunityAdmin
          .includes(:community)
          .where(
            is_boost_bot: true,
            account_status: NewsmastMastodon::CommunityAdmin.account_statuses[:active],
            community: { channel_type: NewsmastMastodon::Community.channel_types[:channel_feed] }
          )
          .pluck(:account_id)
          .uniq
      end
    end
  end
end
