# frozen_string_literal: true

# BOOST-01 request specs. These exercise the real Mastodon routing stack, so
# every example requires the host harness:
#
#   MASTODON_ROOT=/path/to/mastodon BUNDLE_GEMFILE=/path/to/mastodon/Gemfile \
#     bundle exec rspec spec/requests
require "rails_helper"

RSpec.describe "PatchworkExtensions custom boost bot statuses", type: :request do
  let(:oauth_app) { Fabricate(:application) }
  let(:credentials) { { client_id: oauth_app.uid, client_secret: oauth_app.secret } }

  before { require_host! }

  describe "POST /api/v1/custom_statuses/add_custom_boost_bot_status" do
    it "returns 400 when client credentials are missing" do
      post "/api/v1/custom_statuses/add_custom_boost_bot_status",
           params: { status_url: "https://mastodon.social/@test/123" }

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to eq("Client ID and client secret are required")
    end

    it "returns 401 when client credentials are invalid" do
      post "/api/v1/custom_statuses/add_custom_boost_bot_status",
           params: { client_id: oauth_app.uid, client_secret: "wrong-secret", status_url: "https://mastodon.social/@test/123" }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("Invalid client ID or client secret")
    end

    it "returns 400 when status_url is missing" do
      post "/api/v1/custom_statuses/add_custom_boost_bot_status", params: credentials

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to eq("Status URL is required")
    end

    it "returns 404 when no status matches the URL" do
      search_service = instance_double(SearchService, call: { accounts: [], hashtags: [], statuses: [], collections: [] })
      allow(SearchService).to receive(:new).and_return(search_service)

      post "/api/v1/custom_statuses/add_custom_boost_bot_status",
           params: credentials.merge(status_url: "https://mastodon.social/@test/123")

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq("No status found")
    end

    it "adds the resolved status to the custom public timeline" do
      status = Fabricate(:status)
      search_service = instance_double(SearchService, call: { accounts: [], hashtags: [], statuses: [status], collections: [] })
      allow(SearchService).to receive(:new).and_return(search_service)

      timeline_service = instance_double(PatchworkExtensions::CustomTimelineService)
      allow(PatchworkExtensions::CustomTimelineService).to receive(:new).and_return(timeline_service)
      allow(timeline_service).to receive(:add_custom_public_status)

      post "/api/v1/custom_statuses/add_custom_boost_bot_status",
           params: credentials.merge(status_url: "https://mastodon.social/@test/123")

      expect(response).to have_http_status(:ok)
      expect(timeline_service).to have_received(:add_custom_public_status).with(status.id)
    end
  end

  describe "POST /api/v1/custom_statuses/remove_custom_boost_bot_status" do
    it "returns 400 when status_id is missing" do
      post "/api/v1/custom_statuses/remove_custom_boost_bot_status", params: credentials

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to eq("Status ID is required")
    end

    it "returns 404 for an unknown status id" do
      post "/api/v1/custom_statuses/remove_custom_boost_bot_status",
           params: credentials.merge(status_id: "999999999")

      expect(response).to have_http_status(:not_found)
    end

    it "removes the status from the custom public timeline" do
      status = Fabricate(:status)

      timeline_service = instance_double(PatchworkExtensions::CustomTimelineService)
      allow(PatchworkExtensions::CustomTimelineService).to receive(:new).and_return(timeline_service)
      allow(timeline_service).to receive(:remove_custom_public_status)

      post "/api/v1/custom_statuses/remove_custom_boost_bot_status",
           params: credentials.merge(status_id: status.id)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["message"]).to eq("Status removed from custom boost bot timeline")
      expect(timeline_service).to have_received(:remove_custom_public_status).with(status.id.to_s)
    end
  end
end
