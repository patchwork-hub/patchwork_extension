# frozen_string_literal: true

# CMS-02 Ghost Newsletter Subscription request specs. These exercise the real
# Mastodon authentication and user stack, so each example requires the host
# harness:
#
#   MASTODON_ROOT=/path/to/mastodon BUNDLE_GEMFILE=/path/to/mastodon/Gemfile \
#     bundle exec rspec spec/requests/patchwork_extensions/api/v1/accounts/ghost_subscriptions_spec.rb
require "rails_helper"
# The before block stubs HTTParty before any request autoloads the controller
# (which requires httparty), so require it explicitly — otherwise the constant
# is undefined when this file runs before any httparty-loading spec.
require "httparty"

RSpec.describe "PatchworkExtensions Ghost subscriptions", type: :request do
  let(:user) { u = Fabricate(:user); u.update_column(:approved, true); u }
  let(:client_app) { Fabricate(:application, scopes: token_scopes) }
  let(:token_scopes) { "read write" }
  let(:token) do
    Fabricate(:accessible_access_token, resource_owner_id: user.id, application: client_app, scopes: token_scopes)
  end
  let(:headers) { { "Authorization" => "Bearer #{token.token}" } }

  before do
    require_host!
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("GHOST_URL").and_return("https://ghost.example.com")
    allow(ENV).to receive(:[]).with("GHOST_ADMIN_API_KEY").and_return("ghost-test-key:ghost-test-secret")
    allow(HTTParty).to receive(:get).and_return(
      instance_double("HTTParty::Response", success?: true, parsed_response: { "members" => [] })
    )
    allow(HTTParty).to receive(:post).and_return(
      instance_double("HTTParty::Response", success?: true, body: "{}")
    )
  end

  describe "POST /api/v1/accounts/subscribe_leicester" do
    it "creates a Ghost member for a new email" do
      post "/api/v1/accounts/subscribe_leicester", headers: headers, params: { email: "user@example.com", subscribe: true }

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["message"]).to eq("New member subscribed")
      expect(HTTParty).to have_received(:post)
    end

    it "requires authentication" do
      post "/api/v1/accounts/subscribe_leicester", params: { email: "user@example.com", subscribe: true }

      # doorkeeper_authorize! runs before require_user!, so unauthenticated
      # requests get 401 (see AUTH-06's documented contract). The host's 4.6.5
      # upgrade changed the previously observed 422 to 401.
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
