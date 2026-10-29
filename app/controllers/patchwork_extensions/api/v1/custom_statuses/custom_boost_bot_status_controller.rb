# frozen_string_literal: true

module PatchworkExtensions::Api::V1::CustomStatuses
  # BOOST-01: Custom Boost-Bot Status Operations.
  # Extracted from NewsmastMastodon::Api::V1::CustomStatuses::CustomBoostBotStatusController.
  # Preserves the original endpoint URLs, params, response shapes and error
  # statuses. The timeline writes use the Gem B CustomTimelineService copy
  # (FEED-02), which targets the same Redis key as Gem A's.
  # NOTE: authentication is client_id/client_secret in the POST body (any valid
  # Doorkeeper application), matching the Gem A original — flagged for
  # follow-up security review.
  class CustomBoostBotStatusController < ::Api::BaseController
    include Redisable if defined?(Redisable)

    before_action :require_auth!

    RESULTS_LIMIT = 20

    def add_custom_boost_bot_status
      @status_url = params[:status_url]
      return render json: { error: "Status URL is required" }, status: :bad_request unless @status_url.present?

      @search = Search.new(search_results)

      if @search.statuses.any?
        PatchworkExtensions::CustomTimelineService.new.add_custom_public_status(@search.statuses.first.id)
        render json: @search, serializer: REST::SearchSerializer
      else
        render json: { error: "No status found" }, status: :not_found
      end
    end

    def remove_custom_boost_bot_status
      status_id = params[:status_id]
      return render json: { error: "Status ID is required" }, status: :bad_request unless status_id.present?

      status = Status.find(status_id)
      return render json: { error: "Status not found" }, status: :not_found unless status.present?

      PatchworkExtensions::CustomTimelineService.new.remove_custom_public_status(status_id)
      render json: { message: "Status removed from custom boost bot timeline" }
    end

    private

    def search_results
      SearchService.new.call(
        params[:status_url],
        current_account,
        limit_param(RESULTS_LIMIT),
        combined_search_params
      )
    end

    def combined_search_params
      search_params.merge(
        resolve: true,
        exclude_unreviewed: truthy_param?(:exclude_unreviewed),
        following: truthy_param?(:following)
      )
    end

    def search_params
      params.permit(:type, :offset, :min_id, :max_id, :account_id, :following)
    end

    def require_auth!
      return render json: { error: "Client ID and client secret are required" }, status: :bad_request unless params[:client_id].present? && params[:client_secret].present?

      app = Doorkeeper::Application.find_by_uid(params[:client_id])
      return render json: { error: "Invalid client ID or client secret" }, status: :unauthorized unless app.present?

      client_id = app&.uid
      client_secret = app&.secret

      render json: { error: "Invalid client ID or client secret" }, status: :unauthorized unless client_id == params[:client_id] && client_secret == params[:client_secret]
    end
  end
end
