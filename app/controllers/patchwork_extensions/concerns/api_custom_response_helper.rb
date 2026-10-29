# frozen_string_literal: true

# API Response Helper for internationalized API responses.
# Extracted from NewsmastMastodon::Concerns::ApiCustomResponseHelper (AUTH-06);
# behavior is unchanged.

module PatchworkExtensions::Concerns::ApiCustomResponseHelper
  extend ActiveSupport::Concern

  private

  # result response
  def render_result(data = {}, message_key = "api.messages.success", status = :ok, additional_params = {})
    # Use the reusable translation method
    translated_message = get_translated_message(message_key, additional_params)

    response_data = {
      message: translated_message,
      data: data
    }

    render json: response_data, status: status
  end

  def render_response(key:, data:, status: :ok, message_key: nil)
    response_data = { key.to_sym => data }
    response_data[:message] = get_translated_message(message_key) if message_key.present?

    render json: response_data, status: status
  end
end
