# frozen_string_literal: true

# AUTH-04: standalone-capable spec for the role assignment worker.
# Ported from Gem A's spec/workers/newsmast_mastodon/civicrm_role_assignment_worker_spec.rb.
require "rails_helper"

RSpec.describe PatchworkExtensions::CivicrmRoleAssignmentWorker, type: :worker do
  let(:user) { instance_double("User", id: 42, email: "member@example.org", role_id: nil) }
  let(:result) { PatchworkExtensions::CivicrmRoleCheckService::Result.new(values: [ { "id" => 180 } ], group_id: 15) }
  let(:role) { instance_double("UserRole", id: 9) }
  let(:service) { instance_double("PatchworkExtensions::CivicrmRoleCheckService", call: result) }
  let(:eligible_users) { instance_double("ActiveRecord::Relation", update_all: 1) }
  let(:role_scope) { instance_double("ActiveRecord::Relation", first: role) }

  before do
    stub_const("User", class_double("User"))
    stub_const("UserRole", class_double("UserRole"))
    allow(User).to receive(:find_by).with(id: 42).and_return(user)
    allow(PatchworkExtensions::CivicrmRoleCheckService).to receive(:new)
      .with("member@example.org", force_remote: false)
      .and_return(service)
    allow(UserRole).to receive(:where).with("LOWER(name) = ?", "committee member").and_return(role_scope)
    allow(User).to receive(:where).with(id: 42, role_id: nil).and_return(eligible_users)
  end

  it "assigns the highest-priority matching role" do
    described_class.new.perform(42)

    expect(eligible_users).to have_received(:update_all).with(role_id: 9, updated_at: kind_of(ActiveSupport::TimeWithZone))
  end

  it "maps group 16 to the working group role" do
    allow(result).to receive(:group_id).and_return(16)
    allow(UserRole).to receive(:where).with("LOWER(name) = ?", "wg member").and_return(role_scope)

    described_class.new.perform(42)

    expect(UserRole).to have_received(:where).with("LOWER(name) = ?", "wg member")
    expect(eligible_users).to have_received(:update_all).with(role_id: 9, updated_at: kind_of(ActiveSupport::TimeWithZone))
  end

  it "maps group 3 to the staff role" do
    allow(result).to receive(:group_id).and_return(3)
    allow(UserRole).to receive(:where).with("LOWER(name) = ?", "staff").and_return(role_scope)

    described_class.new.perform(42)

    expect(UserRole).to have_received(:where).with("LOWER(name) = ?", "staff")
    expect(eligible_users).to have_received(:update_all).with(role_id: 9, updated_at: kind_of(ActiveSupport::TimeWithZone))
  end

  it "does not overwrite an existing role" do
    allow(user).to receive(:role_id).and_return(7)

    described_class.new.perform(42)

    expect(PatchworkExtensions::CivicrmRoleCheckService).not_to have_received(:new)
    expect(eligible_users).not_to have_received(:update_all)
  end

  it "does nothing when CiviCRM returns no matching group" do
    allow(result).to receive(:values).and_return([])
    allow(result).to receive(:transient_error).and_return(false)

    described_class.new.perform(42)

    expect(UserRole).not_to have_received(:where)
    expect(eligible_users).not_to have_received(:update_all)
  end

  it "raises for transient CiviCRM failures so Sidekiq can retry" do
    transient_result = PatchworkExtensions::CivicrmRoleCheckService::Result.new(values: [], group_id: nil, transient_error: true)
    allow(PatchworkExtensions::CivicrmRoleCheckService).to receive(:new)
      .with("member@example.org", force_remote: false)
      .and_return(service)
    allow(service).to receive(:call).and_return(transient_result)

    expect { described_class.new.perform(42) }
      .to raise_error(PatchworkExtensions::CivicrmRoleCheckService::TransientFailure, /CiviCRM role check failed/)

    expect(eligible_users).not_to have_received(:update_all)
  end

  it "logs and skips assignment when the configured role is missing" do
    allow(role_scope).to receive(:first).and_return(nil)
    allow(Rails.logger).to receive(:error)

    described_class.new.perform(42)

    expect(Rails.logger).to have_received(:error).with("CiviCRM role assignment skipped: UserRole 'Committee member' not found")
    expect(eligible_users).not_to have_received(:update_all)
  end

  it "does nothing when the user no longer exists" do
    allow(User).to receive(:find_by).with(id: 42).and_return(nil)

    described_class.new.perform(42)

    expect(PatchworkExtensions::CivicrmRoleCheckService).not_to have_received(:new)
  end

  it "passes force_remote through to the service" do
    allow(PatchworkExtensions::CivicrmRoleCheckService).to receive(:new)
      .with("member@example.org", force_remote: true)
      .and_return(service)

    described_class.new.perform(42, true)

    expect(PatchworkExtensions::CivicrmRoleCheckService).to have_received(:new)
      .with("member@example.org", force_remote: true)
  end
end
