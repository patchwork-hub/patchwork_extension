# frozen_string_literal: true

# AUTH-04: standalone-capable spec for the signup concern's role-assignment
# enqueue and signup-reason default. Ported from Gem A's
# spec/controllers/newsmast_mastodon/concerns/accounts_creation_spec.rb.
require "rails_helper"

RSpec.describe PatchworkExtensions::Concerns::AccountsCreation do
  subject(:controller) do
    Class.new do
      include PatchworkExtensions::Concerns::AccountsCreation
    end.new
  end

  before do
    allow(PatchworkExtensions::CivicrmRoleAssignmentWorker).to receive(:perform_async)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("CSID_ROLE_ASSIGNMENT_ENABLED", "false").and_return("true")
    allow(ENV).to receive(:fetch).with("LOCAL_DOMAIN", nil).and_return("example.test")
  end

  describe "#signup_reason" do
    it "keeps a supplied nonblank reason" do
      expect(controller.send(:signup_reason, "Because I want to join")).to eq("Because I want to join")
    end

    it "uses the signup fallback for blank or missing reasons" do
      expect(controller.send(:signup_reason, "   ")).to eq("Signing up via example.test App")
      expect(controller.send(:signup_reason, nil)).to eq("Signing up via example.test App")
    end
  end

  it "enqueues role assignment for the newly created user" do
    token = instance_double("Doorkeeper::AccessToken", resource_owner_id: 42)

    controller.send(:enqueue_role_assignment, token)

    expect(PatchworkExtensions::CivicrmRoleAssignmentWorker).to have_received(:perform_async).with(42)
  end

  it "does not enqueue when role assignment is disabled" do
    allow(ENV).to receive(:fetch).with("CSID_ROLE_ASSIGNMENT_ENABLED", "false").and_return("false")
    token = instance_double("Doorkeeper::AccessToken", resource_owner_id: 42)

    controller.send(:enqueue_role_assignment, token)

    expect(PatchworkExtensions::CivicrmRoleAssignmentWorker).not_to have_received(:perform_async)
  end

  it "does not enqueue without a resource owner" do
    token = instance_double("Doorkeeper::AccessToken", resource_owner_id: nil)

    controller.send(:enqueue_role_assignment, token)

    expect(PatchworkExtensions::CivicrmRoleAssignmentWorker).not_to have_received(:perform_async)
  end

  it "logs and continues when enqueue fails" do
    token = instance_double("Doorkeeper::AccessToken", resource_owner_id: 42)
    enqueue_error = Class.new(StandardError)
    allow(PatchworkExtensions::CivicrmRoleAssignmentWorker).to receive(:perform_async).and_raise(enqueue_error)
    allow(Rails.logger).to receive(:error)

    expect { controller.send(:enqueue_role_assignment, token) }.not_to raise_error
    expect(Rails.logger).to have_received(:error).with("CiviCRM role assignment enqueue failed: #{enqueue_error}")
  end
end
