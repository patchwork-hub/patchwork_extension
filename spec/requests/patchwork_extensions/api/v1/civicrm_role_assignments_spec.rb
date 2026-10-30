# frozen_string_literal: true

# AUTH-04: host-mode request spec for POST /api/v1/civicrm_role_assign.
# Ported from Gem A's spec/requests/newsmast_mastodon/api/v1/civicrm_role_assignments_spec.rb.
require "rails_helper"

RSpec.describe "PatchworkExtensions Api V1 CivicrmRoleAssignments", type: :request do
  let(:user) { u = Fabricate(:user); u.update_column(:approved, true); u }
  let(:client_app) { Fabricate(:application, scopes: token_scopes) }
  let(:token_scopes) { "read write" }
  let(:token)   { Fabricate(:accessible_access_token, resource_owner_id: user.id, application: client_app, scopes: token_scopes) }
  let(:headers) { { "Authorization" => "Bearer #{token.token}" } }

  let(:role_assignment_enabled) { "true" }

  before do
    allow(PatchworkExtensions::CivicrmRoleAssignmentWorker).to receive(:perform_async)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("CSID_ROLE_ASSIGNMENT_ENABLED", "false").and_return(role_assignment_enabled)
  end

  it "enqueues role assignment for the current user" do
    require_host!
    post "/api/v1/civicrm_role_assign", headers: headers

    expect(response).to have_http_status(:accepted)
    expect(PatchworkExtensions::CivicrmRoleAssignmentWorker).to have_received(:perform_async).with(user.id)
  end

  it "returns 401 without a token" do
    require_host!
    post "/api/v1/civicrm_role_assign"

    expect(response).to have_http_status(:unauthorized)
    expect(PatchworkExtensions::CivicrmRoleAssignmentWorker).not_to have_received(:perform_async)
  end

  context "when CSID_ROLE_ASSIGNMENT_ENABLED is false" do
    let(:role_assignment_enabled) { "false" }

    it "returns 403 without enqueueing" do
      require_host!
      post "/api/v1/civicrm_role_assign", headers: headers

      expect(response).to have_http_status(:forbidden)
      expect(PatchworkExtensions::CivicrmRoleAssignmentWorker).not_to have_received(:perform_async)
    end
  end

  context "with a token lacking write scope" do
    let(:token_scopes) { "read" }

    it "returns 403" do
      require_host!
      post "/api/v1/civicrm_role_assign", headers: headers

      expect(response).to have_http_status(:forbidden)
      expect(PatchworkExtensions::CivicrmRoleAssignmentWorker).not_to have_received(:perform_async)
    end
  end
end
