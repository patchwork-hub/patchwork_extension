# frozen_string_literal: true

# Shared presence/capability checks for Gem B features that consume Gem A's
# patchwork tables (server_settings, patchwork_communities_admins — both stay
# Gem A-owned) plus the host's per-domain product switches. Replaces Gem A's
# separate PatchworkHelper, MoMeHelper and NonChannelHelper with a single
# unified helper.
module PatchworkMastodonHelper
  def patchwork_table_exists?(table_name)
    ActiveRecord::Base.connection.data_source_exists?(table_name)
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
    false
  rescue StandardError => e
    # pg may not be loaded in standalone (dummy-app) mode; rescuing
    # PG::ConnectionBad unconditionally would raise NameError while handling
    # a connection error there.
    raise unless defined?(PG::ConnectionBad) && e.is_a?(PG::ConnectionBad)

    false
  end

  def patchwork_server_settings_exist?
    return false unless patchwork_table_exists?("server_settings")

    return false unless Object.const_defined?("NewsmastMastodon::ServerSetting") &&
                        defined?(NewsmastMastodon::ServerSetting) &&
                        NewsmastMastodon::ServerSetting.respond_to?(:find_by)

    true
  end

  def patchwork_community_admin_exist?
    return false unless patchwork_table_exists?("patchwork_communities_admins")

    return false unless Object.const_defined?("NewsmastMastodon::CommunityAdmin") &&
                        defined?(NewsmastMastodon::CommunityAdmin) &&
                        NewsmastMastodon::CommunityAdmin.respond_to?(:find_by)

    true
  end

  def is_mo_me?
    return true if Rails.env.development?

    return true if ENV.fetch("LOCAL_DOMAIN", nil) == "mo-me.social"

    false
  end

  def is_non_channel?
    return true if Rails.env.development?

    return true unless ENV.fetch("LOCAL_DOMAIN", nil) == "channel.org" || ENV.fetch("LOCAL_DOMAIN", nil) == "staging.patchwork.online"

    false
  end
end
