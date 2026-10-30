# frozen_string_literal: true

# AUTH-04: CSID badge (membership-derived profile fields) maintenance tasks.
# Extracted from Gem A's lib/tasks/newsmast_mastodon/csid_membership_fields.rake
# and re-namespaced to patchwork_extensions; behavior is unchanged. Gem A's
# copies stay runnable during the verification window via its retained services.
namespace :patchwork_extensions do
  desc "Remove CSID Badge account fields (DRY_RUN=true by default)"
  task remove_csid_badge_fields: :environment do
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch("DRY_RUN", "true"))
    batch_size = [ ENV.fetch("BATCH_SIZE", "200").to_i, 1 ].max
    scope = Account.where("fields @> ?", [{ name: "CSID Badge" }].to_json)
    total = scope.count
    removed_accounts = 0
    removed_fields = 0

    puts "Accounts with CSID Badge fields: #{total}"
    puts "Dry run: #{dry_run}"

    scope.find_in_batches(batch_size: batch_size) do |batch|
      batch.each do |account|
        fields = account[:fields]
        next unless fields.is_a?(Array)

        remaining_fields = fields.reject do |field|
          field.is_a?(Hash) && (field["name"] || field[:name]) == "CSID Badge"
        end
        removed_count = fields.size - remaining_fields.size
        next if removed_count.zero?

        unless dry_run
          account.update_columns(fields: remaining_fields, updated_at: Time.current)
          removed_accounts += 1
        end
        removed_fields += removed_count
      end
    end

    puts "Accounts updated: #{removed_accounts}"
    puts "CSID Badge fields #{dry_run ? "to remove" : "removed"}: #{removed_fields}"
  end

  desc "Backfill blank account fields from CiviCRM user_groups"
  task backfill_csid_badge_fields: :environment do
    start_time = Time.current
    batch_size = ENV.fetch("BATCH_SIZE", "200").to_i
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch("DRY_RUN", "false"))
    only_email = ENV.fetch("EMAIL", nil)&.strip&.downcase

    puts "Starting CSID badge fields backfill at #{start_time}"
    puts "Batch size: #{batch_size} | Dry run: #{dry_run}#{only_email.present? ? " | Email filter: #{only_email}" : ""}"

    sql_blank_fields_clause = "accounts.fields IS NULL OR accounts.fields = '[]'::jsonb OR accounts.fields = '{}'::jsonb"

    email_scope = Account.left_outer_joins(:user)
    if only_email.present?
      email_scope = email_scope.where("LOWER(users.email) = ?", only_email)

      matching_accounts = email_scope.distinct.count(:id)
      matching_blank_accounts = email_scope
                                .where(sql_blank_fields_clause)
                                .distinct
                                .count(:id)

      puts "Email diagnostics: matched accounts=#{matching_accounts}, matched accounts with blank fields=#{matching_blank_accounts}"
      if matching_accounts.zero?
        puts "No account found for EMAIL=#{only_email}. CiviCRM service will not be called."
      elsif matching_blank_accounts.zero?
        puts "Account found for EMAIL=#{only_email}, but no SQL-blank fields matched. Continuing with Ruby blank check for EMAIL-targeted run."
      end
    end

    # For a targeted EMAIL run, evaluate blankness in Ruby to catch semantically blank JSON arrays.
    scope = if only_email.present?
              email_scope
    else
              email_scope.where(sql_blank_fields_clause)
    end

    total = scope.distinct.count(:id)
    puts "Accounts with empty fields: #{total}"

    if total.zero?
      puts "No accounts found for processing."
      next
    end

    processed = 0
    updated = 0
    skipped_no_email = 0
    skipped_no_groups = 0
    skipped_invalid_membership = 0
    skipped_already_has_fields = 0
    errors = 0

    scope.select("accounts.id").distinct.find_in_batches(batch_size: batch_size) do |batch|
      account_ids = batch.map(&:id)

      Account.includes(:user).where(id: account_ids).find_each do |account|
        processed += 1

        begin
          email = account.user&.email.to_s.strip

          unless fields_blank?(account[:fields])
            skipped_already_has_fields += 1
            puts "[SKIP] account_id=#{account.id} email=#{email} reason=fields_not_blank" if only_email.present?
            next
          end

          if email.blank?
            skipped_no_email += 1
            puts "[SKIP] account_id=#{account.id} reason=no_email"
            next
          end

          puts "[CALL] account_id=#{account.id} email=#{email} calling_civicrm=true"
          membership_result = PatchworkExtensions::CivicrmMembershipCheckService.new(email, force_remote: true).call
          unless membership_result.valid?
            skipped_invalid_membership += 1
            puts "[SKIP] account_id=#{account.id} email=#{email} reason=membership_invalid"
            next
          end

          new_fields = build_csid_badge_fields(membership_result.user_groups)
          if new_fields.blank?
            skipped_no_groups += 1
            puts "[SKIP] account_id=#{account.id} email=#{email} reason=no_user_groups"
            next
          end

          if dry_run
            puts "[DRY_RUN] account_id=#{account.id} email=#{email} fields=#{new_fields.to_json}"
          else
            account.update_columns(fields: new_fields, updated_at: Time.current)
            puts "[UPDATED] account_id=#{account.id} email=#{email} fields_count=#{new_fields.size}"
          end
          updated += 1
        rescue StandardError => e
          errors += 1
          puts "[ERROR] account_id=#{account.id} message=#{e.message}"
          Rails.logger.error("[patchwork_extensions:backfill_csid_badge_fields] account_id=#{account.id} error=#{e.class} message=#{e.message}\n#{e.backtrace.join("\n")}")
        end
      end

      puts "Progress: #{processed}/#{total} processed"
    end

    duration = (Time.current - start_time).round(2)
    puts "\n#{'=' * 60}"
    puts "CSID BADGE FIELDS BACKFILL SUMMARY"
    puts "Total candidates: #{total}"
    puts "Processed: #{processed}"
    puts "Updated: #{updated}"
    puts "Skipped (no email): #{skipped_no_email}"
    puts "Skipped (membership invalid): #{skipped_invalid_membership}"
    puts "Skipped (no user groups): #{skipped_no_groups}"
    puts "Skipped (already has fields): #{skipped_already_has_fields}"
    puts "Errors: #{errors}"
    puts "Duration: #{duration}s"
    puts "#{'=' * 60}"
  end

  def fields_blank?(raw_fields)
    return true if raw_fields.nil?
    return true if raw_fields == [] || raw_fields == {}

    return false unless raw_fields.is_a?(Array)

    raw_fields.all? do |field|
      next true unless field.is_a?(Hash)

      name = field["name"] || field[:name]
      value = field["value"] || field[:value]
      name.to_s.strip.empty? && value.to_s.strip.empty?
    end
  end

  def build_csid_badge_fields(user_groups)
    filtered_groups = Array(user_groups)
                      .map { |group| group.to_s.strip }
                      .reject(&:blank?)
                      .reject { |group| group.casecmp?("Newsletter sign-up") }
                      .first(4)

    filtered_groups.map { |group| { name: "CSID Badge", value: group } }
  end
end
