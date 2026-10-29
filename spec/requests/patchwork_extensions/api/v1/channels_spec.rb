# frozen_string_literal: true

# COMMUNITY-03 request specs. These exercise the real Mastodon authentication
# and authorization stack, so every example requires the host harness:
#
#   MASTODON_ROOT=/path/to/mastodon BUNDLE_GEMFILE=/path/to/mastodon/Gemfile \
#     bundle exec rspec spec/requests
#
# Fixture data is written to a temporary directory and injected via
# PatchworkExtensions.configuration.starter_pack_data_root, so results are
# deterministic and independent of the packaged JSON datasets.
require "rails_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "PatchworkExtensions starter-pack channels", type: :request do
  let(:data_root) { Pathname.new(Dir.mktmpdir("starter-packs")) }

  let(:user) { u = Fabricate(:user); u.update_column(:approved, true); u }
  let(:client_app) { Fabricate(:application, scopes: token_scopes) }
  let(:token_scopes) { "read write" }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, application: client_app, scopes: token_scopes) }
  let(:headers) { { "Authorization" => "Bearer #{token.token}" } }

  let(:channel) { { "id" => "1", "title" => "Fun, Funny and Fantastic", "total_accounts" => 2 } }
  let(:followers) { [ { "id" => "10", "acct" => "alice@example.com" } ] }

  before do
    require_host!

    FileUtils.mkdir_p(data_root.join("twt"))
    File.write(data_root.join("twt/starter_pack_list.json"), [ channel ].to_json)
    File.write(data_root.join("twt/starter_pack_1.json"), followers.to_json)

    PatchworkExtensions.configuration.starter_pack_data_root = data_root
  end

  after do
    PatchworkExtensions.reset_configuration!
    FileUtils.remove_entry(data_root)
  end

  describe "GET /api/v1/channels/starter_packs_channels" do
    it "returns the fixture channel list" do
      get "/api/v1/channels/starter_packs_channels", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("data" => [ channel ])
    end

    it "returns an empty data array when the list file is missing" do
      FileUtils.rm(data_root.join("twt/starter_pack_list.json"))

      get "/api/v1/channels/starter_packs_channels", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("data" => [])
    end

    it "falls back to the twt namespace for unknown sources" do
      get "/api/v1/channels/starter_packs_channels",
          params: { starter_pack_source: "no-such-source" },
          headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("data" => [ channel ])
    end

    it "requires authentication" do
      get "/api/v1/channels/starter_packs_channels", headers: {}

      # Mastodon's require_user! responds 422, not 401, for missing auth.
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /api/v1/channels/:id/starter_packs_detail" do
    it "returns the channel and its followers" do
      get "/api/v1/channels/1/starter_packs_detail", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("channel" => channel, "followers" => followers)
    end

    it "returns 404 for an unknown pack" do
      get "/api/v1/channels/999/starter_packs_detail", headers: headers

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq("error" => "Channel not found")
    end

    it "returns 404 when the list file is missing" do
      FileUtils.rm(data_root.join("twt/starter_pack_list.json"))

      get "/api/v1/channels/1/starter_packs_detail", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "returns empty followers when the followers file is missing" do
      FileUtils.rm(data_root.join("twt/starter_pack_1.json"))

      get "/api/v1/channels/1/starter_packs_detail", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("channel" => channel, "followers" => [])
    end
  end
end
