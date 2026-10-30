# frozen_string_literal: true

# MEDIA-01 alt-text settings request specs. These exercise the real Mastodon
# authentication and user stack (including the `alttext_enabled` column), so
# every example requires the host harness:
#
#   MASTODON_ROOT=/path/to/mastodon BUNDLE_GEMFILE=/path/to/mastodon/Gemfile \
#     bundle exec rspec spec/requests
require "rails_helper"

RSpec.describe "PatchworkExtensions alt-text settings", type: :request do
  let(:user) { u = Fabricate(:user); u.update_column(:approved, true); u }
  let(:client_app) { Fabricate(:application, scopes: token_scopes) }
  let(:token_scopes) { "read write" }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, application: client_app, scopes: token_scopes) }
  let(:headers) { { "Authorization" => "Bearer #{token.token}" } }

  before { require_host! }

  describe "GET /api/v1/patchwork/alttext_settings" do
    it "returns the user's current alt-text preference" do
      user.update_column(:alttext_enabled, true)

      get "/api/v1/patchwork/alttext_settings", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to have_key("message")
      expect(response.parsed_body["data"]).to be(true)
    end

    it "requires authentication" do
      get "/api/v1/patchwork/alttext_settings"

      # doorkeeper_authorize! runs before require_user! in this controller, so
      # missing auth gets Doorkeeper's 401, not Mastodon's 422 (same contract
      # as AUTH-06's /patchwork/account_deletion).
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/patchwork/alttext_settings/alttext" do
    it "enables alt text with a truthy enabled param" do
      post "/api/v1/patchwork/alttext_settings/alttext",
           headers: headers,
           params: { enabled: "true" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]).to be(true)
      expect(user.reload.alttext_enabled).to be(true)
    end

    it "disables alt text with a falsey enabled param" do
      user.update_column(:alttext_enabled, true)

      post "/api/v1/patchwork/alttext_settings/alttext",
           headers: headers,
           params: { enabled: "false" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]).to be(false)
      expect(user.reload.alttext_enabled).to be(false)
    end

    it "propagates a not-null violation when enabled is missing" do
      # Gem A contract quirk, preserved unchanged: the boolean cast turns a
      # missing/non-boolean `enabled` param into nil, and the host's
      # users.alttext_enabled column is NOT NULL, so the update raises instead
      # of toggling the flag. Flagged for follow-up review.
      user.update_column(:alttext_enabled, true)

      expect do
        post "/api/v1/patchwork/alttext_settings/alttext", headers: headers
      end.to raise_error(ActiveRecord::NotNullViolation)
      expect(user.reload.alttext_enabled).to be(true)
    end

    it "requires authentication" do
      post "/api/v1/patchwork/alttext_settings/alttext", params: { enabled: "true" }

      # doorkeeper_authorize! runs before require_user! in this controller, so
      # missing auth gets Doorkeeper's 401, not Mastodon's 422.
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
