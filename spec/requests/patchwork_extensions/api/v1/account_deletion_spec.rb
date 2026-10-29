# frozen_string_literal: true

# AUTH-06 account deletion request specs. These exercise the real Mastodon
# authentication, user and account stack, so every example requires the host
# harness:
#
#   MASTODON_ROOT=/path/to/mastodon BUNDLE_GEMFILE=/path/to/mastodon/Gemfile \
#     bundle exec rspec spec/requests
require "rails_helper"

RSpec.describe "PatchworkExtensions account deletion", type: :request do
  let(:user) { u = Fabricate(:user); u.update_column(:approved, true); u }
  let(:client_app) { Fabricate(:application, scopes: token_scopes) }
  let(:token_scopes) { "read write" }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, application: client_app, scopes: token_scopes) }
  let(:headers) { { "Authorization" => "Bearer #{token.token}" } }

  before { require_host! }

  describe "POST /api/v1/delete_account" do
    it "suspends the account and enqueues deletion when the password is correct" do
      allow(AccountDeletionWorker).to receive(:perform_async)

      post "/api/v1/delete_account", headers: headers, params: { password: "123456789" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("message" => "Resource deleted successfully", "data" => {})
      expect(user.account.reload.suspended?).to be(true)
      expect(AccountDeletionWorker).to have_received(:perform_async)
        .with(user.account.id, { "reserve_username" => true })
    end

    it "returns 422 and does not delete when the password is incorrect" do
      allow(AccountDeletionWorker).to receive(:perform_async)

      post "/api/v1/delete_account", headers: headers, params: { password: "wrong-password" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include("message" => "Current password is incorrect", "data" => {})
      expect(user.account.reload.suspended?).to be(false)
      expect(AccountDeletionWorker).not_to have_received(:perform_async)
    end

    it "requires authentication" do
      post "/api/v1/delete_account", params: { password: "123456789" }

      # require_user! runs before doorkeeper_authorize! in this controller, so
      # missing auth gets Mastodon's 422, not Doorkeeper's 401.
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /api/v1/patchwork/account_deletion/:id" do
    it "deletes the requester's own account and returns accepted" do
      service = instance_double(DeleteAccountService, call: nil)
      allow(DeleteAccountService).to receive(:new).and_return(service)

      delete "/api/v1/patchwork/account_deletion/#{user.account.id}", headers: headers

      expect(DeleteAccountService).to have_received(:new)
      expect(service).to have_received(:call).with(user.account, reserve_email: false, reserve_username: false)
      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body).to include("message" => "Resource deleted successfully", "data" => {})
    end

    # Current contract preserved from Gem A, flagged for follow-up security
    # review: any authenticated user can delete any account by id.
    it "deletes accounts other than the requester's (no identity isolation)" do
      target = Fabricate(:account)
      service = instance_double(DeleteAccountService, call: nil)
      allow(DeleteAccountService).to receive(:new).and_return(service)

      delete "/api/v1/patchwork/account_deletion/#{target.id}", headers: headers

      expect(response).to have_http_status(:accepted)
      expect(service).to have_received(:call).with(target, reserve_email: false, reserve_username: false)
    end

    it "returns 404 for an unknown account" do
      delete "/api/v1/patchwork/account_deletion/-1", headers: headers

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to have_key("error")
    end

    it "requires authentication" do
      delete "/api/v1/patchwork/account_deletion/#{user.account.id}"

      # doorkeeper_authorize! runs before require_user! in this controller, so
      # missing auth gets a 401 from Doorkeeper, not Mastodon's 422.
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
