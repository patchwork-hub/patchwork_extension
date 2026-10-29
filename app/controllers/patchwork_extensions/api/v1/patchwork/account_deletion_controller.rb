# frozen_string_literal: true

module PatchworkExtensions::Api::V1::Patchwork
  # AUTH-06: Account Deletion (id-based deletion entry point).
  # Extracted from NewsmastMastodon::Api::V1::Patchwork::AccountDeletionController.
  # Preserves the original endpoint URL, response shapes and OAuth/before_action
  # behavior (doorkeeper_authorize! runs before require_user!, so missing auth
  # responds 401).
  #
  # SECURITY NOTE (inherited from Gem A, flagged for follow-up review): this
  # endpoint deletes ANY account by id for any authenticated user; there is no
  # ownership or admin check. The contract is preserved as-is for the split.
  class AccountDeletionController < ::Api::BaseController
    include ::PatchworkExtensions::Concerns::ApiResponseHelper

    before_action -> { doorkeeper_authorize! :read, :write }
    before_action :require_user!
    before_action :set_account, only: [ :destroy ]

    # DELETE /api/v1/patchwork/account_deletion/:id
    def destroy
      if @account.nil?
        render_error("api.errors.not_found", :not_found)
        return
      end

      DeleteAccountService.new.call(@account, reserve_email: false, reserve_username: false)
      render_success({}, "api.messages.deleted", :accepted)
    end

    private

    def set_account
      @account = Account.find_by(id: params[:id])
    end
  end
end
