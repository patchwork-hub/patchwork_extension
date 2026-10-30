# frozen_string_literal: true

# AUTH-04: host-mode request spec for the signup membership gate on
# POST /api/v1/accounts. Ported from Gem A's
# spec/requests/newsmast_mastodon/api/v1/accounts_registration_membership_spec.rb.
require "rails_helper"

RSpec.describe "PatchworkExtensions Api V1 Accounts Registration Membership", type: :request do
  let(:client_app) { Fabricate(:application, scopes: "read write") }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: nil, application: client_app, scopes: "write") }
  let(:headers) { { "Authorization" => "Bearer #{token.token}" } }
  let(:email) { "blocked@example.org" }

  let(:registration_params) do
    {
      username: "blocked_#{SecureRandom.hex(4)}",
      email: email,
      password: "Password123!",
      agreement: true,
      locale: "en"
    }
  end

  it "POST /api/v1/accounts returns 422 when membership check fails" do
    require_host!

    failure_message = I18n.t("api.account.errors.membership_not_eligible")
    invalid_result = PatchworkExtensions::CivicrmMembershipCheckService::Result.new(valid?: false, error_message: failure_message)
    membership_service = instance_double("PatchworkExtensions::CivicrmMembershipCheckService", call: invalid_result)

    allow(PatchworkExtensions::CivicrmMembershipCheckService).to receive(:new).with(email).and_return(membership_service)
    expect(AppSignUpService).not_to receive(:new)

    post "/api/v1/accounts", headers: headers, params: registration_params

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include(failure_message)
  end
end
