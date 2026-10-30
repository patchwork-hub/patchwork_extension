# frozen_string_literal: true

# AUTH-04: asynchronous CiviCRM role assignment.
# Extracted from NewsmastMastodon::CivicrmRoleAssignmentWorker; queue, retry
# policy and group-to-role mapping are preserved unchanged. Gem A's worker
# class stays so jobs queued before the cutover still deserialize (INFRA-05).
module PatchworkExtensions
  class CivicrmRoleAssignmentWorker
    include Sidekiq::Worker

    ROLE_NAMES_BY_GROUP_ID = {
      15 => "Committee member",
      16 => "WG member",
      3 => "Staff"
    }.freeze

    sidekiq_options queue: "default", retry: 3

    def self.role_name_for(group_id)
      ROLE_NAMES_BY_GROUP_ID[group_id]
    end

    def perform(user_id, force_remote = false)
      user = User.find_by(id: user_id)
      return unless user
      return if user.role_id.present? || user.email.blank?

      result = PatchworkExtensions::CivicrmRoleCheckService.new(user.email, force_remote: force_remote).call
      if result.transient_error
        raise PatchworkExtensions::CivicrmRoleCheckService::TransientFailure,
              "CiviCRM role check failed for #{user.email}"
      end
      return if result.values.blank?

      role_name = self.class.role_name_for(result.group_id)
      return if role_name.blank?

      role = UserRole.where("LOWER(name) = ?", role_name.downcase).first
      unless role
        Rails.logger.error("CiviCRM role assignment skipped: UserRole '#{role_name}' not found")
        return
      end

      User.where(id: user.id, role_id: nil).update_all(role_id: role.id, updated_at: Time.current)
    end
  end
end
