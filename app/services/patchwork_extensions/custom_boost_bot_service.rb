# frozen_string_literal: true

module PatchworkExtensions
  # BOOST-01: Custom Boost-Bot Status Operations (client side).
  # Extracted from NewsmastMastodon::CustomBoostBotService. Calls a configured
  # remote instance's add_custom_boost_bot_status endpoint using per-username
  # ENV credentials.
  #
  # NOTE: Gem A keeps its own copy active because
  # NewsmastMastodon::ReblogChannelsWorker (COMMUNITY-02, not yet assigned)
  # still calls it; referencing this Gem B class from the Gem A worker would be
  # a Gem A -> Gem B reverse dependency. Remove Gem A's copy when
  # COMMUNITY-02/BOOST-02 migrate.
  class CustomBoostBotService < BaseService
    require "httparty"

    def initialize(status_id, username)
      @base_url = ENV.fetch("#{username.upcase}_INSTANCE_URL", nil)
      @client_id = ENV.fetch("#{username.upcase}_CLIENT_ID", nil)
      @client_secret = ENV.fetch("#{username.upcase}_CLIENT_SECRET", nil)
      @status = Status.find_by(id: status_id)
    end

    def call
      return false unless @status
      url = @base_url + "/api/v1/custom_statuses/add_custom_boost_bot_status"

      status_url = build_status_url

      response = HTTParty.post(url,
                    body: {
                        client_id: @client_id,
                        client_secret: @client_secret,
                        status_url: status_url
                    }.to_json,
                    headers: { "Content-Type" => "application/json" })
    end

    private

    def build_status_url
      account = @status.account
      acct = local? ? "@#{account.username}" : "@#{account.username}@#{account.domain}"
      status_url = "https://#{ENV['LOCAL_DOMAIN']}/#{acct}/#{@status.id}"
    end

    def local?
      @status.account.domain.nil?
    end
  end
end
