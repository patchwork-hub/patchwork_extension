# frozen_string_literal: true

# AUTH-04: CSID role backfill maintenance task.
# Extracted from Gem A's lib/tasks/newsmast_mastodon/csid_role_assignment.rake
# and re-namespaced to patchwork_extensions; behavior is unchanged. Gem A's
# copy stays runnable during the verification window via its retained
# worker/services.
namespace :patchwork_extensions do
  desc "Assign roles to existing users from CiviCRM group membership"
  task backfill_csid_roles: :environment do
    start_time = Time.current
    batch_size = ENV.fetch("BATCH_SIZE", "200").to_i
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch("DRY_RUN", "false"))
    async = ActiveModel::Type::Boolean.new.cast(ENV.fetch("ASYNC", "true"))
    only_email = ENV.fetch("EMAIL", nil)&.strip&.downcase

    scope = User.where(role_id: nil).where.not(email: [ nil, "" ])
    scope = scope.where("LOWER(users.email) = ?", only_email) if only_email.present?

    total = scope.count
    processed = 0
    enqueued = 0
    assigned = 0
    unmatched = 0
    errors = 0

    puts "Starting CSID role backfill at #{start_time}"
    puts "Candidates: #{total} | Batch size: #{batch_size} | Dry run: #{dry_run} | Async: #{async}"

    scope.find_each(batch_size: batch_size) do |user|
      processed += 1

      if dry_run
        result = PatchworkExtensions::CivicrmRoleCheckService.new(user.email, force_remote: true).call
        if result.values.present?
          role_name = PatchworkExtensions::CivicrmRoleAssignmentWorker.role_name_for(result.group_id)
          assigned += 1
          puts "[DRY_RUN] user_id=#{user.id} email=#{user.email} role=#{role_name} group_id=#{result.group_id}"
        else
          unmatched += 1
          puts "[SKIP] user_id=#{user.id} email=#{user.email} reason=no_matching_group"
        end
      elsif async
        PatchworkExtensions::CivicrmRoleAssignmentWorker.perform_async(user.id, true)
        enqueued += 1
        puts "[ENQUEUED] user_id=#{user.id} email=#{user.email}"
      else
        PatchworkExtensions::CivicrmRoleAssignmentWorker.new.perform(user.id, true)
        user.reload
        if user.role_id.present?
          assigned += 1
          puts "[ASSIGNED] user_id=#{user.id} email=#{user.email} role_id=#{user.role_id}"
        else
          unmatched += 1
          puts "[SKIP] user_id=#{user.id} email=#{user.email} reason=no_role_assigned"
        end
      end
    rescue StandardError => e
      errors += 1
      puts "[ERROR] user_id=#{user.id} email=#{user.email} message=#{e.message}"
      Rails.logger.error("[patchwork_extensions:backfill_csid_roles] user_id=#{user.id} error=#{e.class} message=#{e.message}")
    end

    duration = (Time.current - start_time).round(2)
    puts "\n#{'=' * 60}"
    puts "CSID ROLE BACKFILL SUMMARY"
    puts "Total candidates: #{total}"
    puts "Processed: #{processed}"
    puts "Enqueued: #{enqueued}"
    puts dry_run ? "Would assign: #{assigned}" : "Assigned inline: #{assigned}"
    puts "Unmatched/skipped: #{unmatched}"
    puts "Errors: #{errors}"
    puts "Duration: #{duration}s"
    puts "#{'=' * 60}"
  end
end
