# frozen_string_literal: true

module NonChannelHelper
  extend ActiveSupport::Concern

  def is_non_channel?
    return true if Rails.env.development?

    return true unless ENV.fetch("LOCAL_DOMAIN", nil) == "channel.org" || ENV.fetch("LOCAL_DOMAIN", nil) == "staging.patchwork.online"

    false
  end
end
