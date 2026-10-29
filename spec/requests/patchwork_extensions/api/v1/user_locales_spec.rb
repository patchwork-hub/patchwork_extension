# frozen_string_literal: true

# AUTH-06 user locale request specs. These exercise the real Mastodon
# authentication and user stack, so every example requires the host harness:
#
#   MASTODON_ROOT=/path/to/mastodon BUNDLE_GEMFILE=/path/to/mastodon/Gemfile \
#     bundle exec rspec spec/requests
require "rails_helper"

RSpec.describe "PatchworkExtensions user locales", type: :request do
  let(:user) { u = Fabricate(:user); u.update_column(:approved, true); u }
  let(:client_app) { Fabricate(:application, scopes: token_scopes) }
  let(:token_scopes) { "read write" }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, application: client_app, scopes: token_scopes) }
  let(:headers) { { "Authorization" => "Bearer #{token.token}" } }

  before { require_host! }

  describe "POST /api/v1/user_locales" do
    it "saves the user's locale preference" do
      post "/api/v1/user_locales", headers: headers, params: { lang: "fr" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to have_key("message")
      expect(response.parsed_body.dig("data", "locale")).to eq("fr")
      expect(user.reload.locale).to eq("fr")
    end

    it "rejects an unsupported locale with the list of available locales" do
      post "/api/v1/user_locales", headers: headers, params: { lang: "xx_invalid" }

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body).to have_key("errors")
      expect(response.parsed_body["available_locales"]).to be_an(Array)
      expect(user.reload.locale).not_to eq("xx_invalid")
    end

    it "rejects a missing lang parameter" do
      post "/api/v1/user_locales", headers: headers

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/user_locales", params: { lang: "fr" }

      # require_user! runs before doorkeeper_authorize! in this controller, so
      # missing auth gets Mastodon's 422, not Doorkeeper's 401.
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
