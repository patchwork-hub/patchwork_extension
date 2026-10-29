# frozen_string_literal: true

module PatchworkExtensions::Api::V1
  # COMMUNITY-03: Starter-Pack Discovery.
  # Extracted from NewsmastMastodon::Api::V1::ChannelsController. Preserves the
  # original endpoint URLs, response shapes, authentication, source-namespace
  # selection, and modification-time-validated Redis caching.
  class ChannelsController < ::Api::BaseController
    include Redisable if defined?(Redisable)

    before_action :require_user!
    before_action -> { doorkeeper_authorize! :read, :write }

    # GET /api/v1/channels/starter_packs_channels
    # Returns the list of starter pack channels from JSON data
    def starter_packs_channels
      list_relative = starter_pack_data_path("starter_pack_list.json")
      full_path = starter_pack_data_root.join(list_relative)

      # Return empty response if file doesn't exist
      unless File.exist?(full_path)
        render json: { data: [] } and return
      end

      # Set HTTP caching headers based on file modification time
      last_modified = File.mtime(full_path)
      if stale?(last_modified: last_modified, etag: "#{starter_pack_namespace}-#{last_modified.to_i}")
        starter_packs_channels = load_json_data(list_relative)

        expires_in 24.hours, public: true

        render json: { data: starter_packs_channels }
      end
    end

    # GET /api/v1/channels/:id/starter_packs_detail
    # Returns details of a specific starter pack channel including followers
    def starter_packs_detail
      channel_id = params[:id]
      list_relative = starter_pack_data_path("starter_pack_list.json")
      list_path = starter_pack_data_root.join(list_relative)

      unless File.exist?(list_path)
        render json: { error: "Channel not found" }, status: :not_found and return
      end

      followers_relative = starter_pack_data_path("starter_pack_#{channel_id}.json")
      followers_path = starter_pack_data_root.join(followers_relative)

      list_mtime = File.mtime(list_path)
      followers_mtime = File.exist?(followers_path) ? File.mtime(followers_path) : list_mtime
      last_modified = [ list_mtime, followers_mtime ].max

      if stale?(last_modified: last_modified, etag: "#{starter_pack_namespace}-#{channel_id}-#{last_modified.to_i}")
        starter_packs_channels = load_json_data(list_relative)
        channel = starter_packs_channels.find { |ch| ch["id"] == channel_id }

        unless channel
          render json: { error: "Channel not found" }, status: :not_found and return
        end

        followers = load_json_data(followers_relative)

        expires_in 24.hours, public: true

        render json: {
          channel: channel,
          followers: followers
        }
      end
    end

    private

    def starter_pack_data_root
      PatchworkExtensions.configuration.resolved_starter_pack_data_root
    end

    def load_json_data(relative_path)
      with_redis do |redis|
        PatchworkExtensions::StarterPackData
          .new(redis: redis, data_root: starter_pack_data_root)
          .load(relative_path, namespace: starter_pack_namespace)
      end
    end

    def starter_pack_data_path(filename)
      File.join(starter_pack_namespace, filename)
    end

    # Determine the namespace/source for starter pack data
    def starter_pack_namespace
      source = params[:starter_pack_source]
      normalized_source = source.present? ? source.to_s.parameterize(separator: "") : nil

      case normalized_source
      when "thebristolcable"
        "thebristolcable"
      when "twt"
        "twt"
      when "findout"
        "findout"
      when "leicestergazette"
        "leicestergazette"
      else
        "twt"
      end
    end
  end
end
