# frozen_string_literal: true

# CONV-01 request specs. These exercise the real Mastodon authentication and
# conversation stack, so every example requires the host harness:
#
#   MASTODON_ROOT=/path/to/mastodon BUNDLE_GEMFILE=/path/to/mastodon/Gemfile \
#     bundle exec rspec spec/requests
require "rails_helper"

RSpec.describe "PatchworkExtensions conversations", type: :request do
  let(:user) { u = Fabricate(:user); u.update_column(:approved, true); u }
  let(:client_app) { Fabricate(:application, scopes: token_scopes) }
  let(:token_scopes) { "read write read:statuses write:conversations" }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, application: client_app, scopes: token_scopes) }
  let(:headers) { { "Authorization" => "Bearer #{token.token}" } }

  let(:other) { Fabricate(:account) }

  before { require_host! }

  def create_account_conversation(account:, participants:, unread: true)
    Fabricate(
      :account_conversation,
      account: account,
      conversation: Fabricate(:conversation),
      participant_account_ids: participants.map(&:id),
      unread: unread
    )
  end

  describe "GET /api/v1/patchwork/conversations/check_conversation" do
    it "returns an empty object when no conversation exists with the target" do
      get "/api/v1/patchwork/conversations/check_conversation",
          headers: headers,
          params: { target_account_id: other.id }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({})
    end

    it "returns an empty object when target_account_id is missing" do
      get "/api/v1/patchwork/conversations/check_conversation", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({})
    end

    it "returns the conversation with the target participant" do
      account_conversation = create_account_conversation(account: user.account, participants: [ other ])

      get "/api/v1/patchwork/conversations/check_conversation",
          headers: headers,
          params: { target_account_id: other.id }

      expect(response).to have_http_status(:ok)
      # The host's REST::ConversationSerializer exposes the AccountConversation
      # id (object.id), not the conversation id.
      expect(response.parsed_body["id"]).to eq(account_conversation.id.to_s)
      expect(response.parsed_body["unread"]).to be(true)
      expect(response.parsed_body["accounts"].map { |a| a["id"] }).to include(other.id.to_s)
    end

    it "does not return conversations that belong to another account" do
      create_account_conversation(account: Fabricate(:account), participants: [ other ])

      get "/api/v1/patchwork/conversations/check_conversation",
          headers: headers,
          params: { target_account_id: other.id }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({})
    end

    it "does not return conversations with a different participant" do
      create_account_conversation(account: user.account, participants: [ Fabricate(:account) ])

      get "/api/v1/patchwork/conversations/check_conversation",
          headers: headers,
          params: { target_account_id: other.id }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({})
    end

    it "requires authentication" do
      get "/api/v1/patchwork/conversations/check_conversation",
          params: { target_account_id: other.id }

      # doorkeeper_authorize! runs before require_user! in this controller, so
      # missing auth gets a 401 from Doorkeeper, not Mastodon's 422.
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/patchwork/conversations/read_all" do
    it "marks only the current account's unread conversations as read" do
      create_account_conversation(account: user.account, participants: [ other ])
      create_account_conversation(account: user.account, participants: [ Fabricate(:account) ])
      foreign = create_account_conversation(account: Fabricate(:account), participants: [ other ])

      post "/api/v1/patchwork/conversations/read_all", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("success" => true, "updated_count" => 2)
      expect(AccountConversation.where(account: user.account, unread: true)).to be_empty
      expect(foreign.reload.unread).to be(true)
    end

    it "reports zero when there is nothing unread" do
      post "/api/v1/patchwork/conversations/read_all", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("success" => true, "updated_count" => 0)
    end

    it "requires authentication" do
      post "/api/v1/patchwork/conversations/read_all"

      # doorkeeper_authorize! runs before require_user! in this controller, so
      # missing auth gets a 401 from Doorkeeper, not Mastodon's 422.
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
