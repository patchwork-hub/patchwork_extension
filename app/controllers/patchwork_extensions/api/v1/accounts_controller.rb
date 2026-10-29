# frozen_string_literal: true

module PatchworkExtensions::Api::V1
  # AUTH-06: Account Deletion (password-confirmed self-deletion entry point).
  # Extracted from NewsmastMastodon::Api::V1::AccountsController.
  # Preserves the original endpoint URL, request params, response shapes and
  # OAuth/before_action behavior (require_user! runs before
  # doorkeeper_authorize!, so missing auth responds 422).
  class AccountsController < ::Api::BaseController
    include Redisable if defined?(Redisable)
    include ::PatchworkExtensions::Concerns::ApiResponseHelper

    before_action :require_user!
    before_action -> { doorkeeper_authorize! :read, :write }

    # POST /api/v1/delete_account
    def delete_account
      if current_user.valid_password?(account_params[:password])
        current_account.suspend!(origin: :local, block_email: false)
        AccountDeletionWorker.perform_async(current_user.account_id, { "reserve_username" => true })
        sign_out
        render_success(data = {}, message_key = "api.messages.deleted", status = :ok, additional_params = {})
      else
        render_result({}, "api.account.errors.password_incorrect", :unprocessable_entity)
      end
    end

    private

    def account_params
      params.permit(:password)
    end
  end
end
