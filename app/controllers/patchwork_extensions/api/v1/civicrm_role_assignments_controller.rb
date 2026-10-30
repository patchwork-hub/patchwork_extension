# frozen_string_literal: true

module PatchworkExtensions::Api::V1
  # AUTH-04: self-service CiviCRM role assignment.
  # Extracted from NewsmastMastodon::Api::V1::CivicrmRoleAssignmentsController.
  # Preserves the original endpoint URL, response shapes and OAuth scope.
  class CivicrmRoleAssignmentsController < ::Api::BaseController
    include ::PatchworkExtensions::Concerns::ApiResponseHelper

    before_action -> { doorkeeper_authorize! :write }
    before_action :require_user!

    # POST /api/v1/civicrm_role_assign
    def create
      return render_forbidden unless role_assignment_enabled?

      PatchworkExtensions::CivicrmRoleAssignmentWorker.perform_async(current_user.id)
      render_success({}, "api.messages.success", :accepted)
    rescue StandardError => e
      Rails.logger.error("CiviCRM role assignment enqueue failed: #{e.class}")
      render_internal_error
    end

    private

    def role_assignment_enabled?
      ActiveModel::Type::Boolean.new.cast(ENV.fetch("CSID_ROLE_ASSIGNMENT_ENABLED", "false"))
    end
  end
end
