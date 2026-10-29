# frozen_string_literal: true

module PatchworkExtensions
  module Api
    module V1
      module Timelines
        class ForYouCustomTimelineController < ::Api::V1::Timelines::BaseController
          include NewsmastMastodon::Overrides::TimelinePatchworkPostReactions

          before_action -> { doorkeeper_authorize! :read, :'read:statuses' }
          before_action :require_user!
          before_action :validate_requested_domains!, only: :show

          PERMITTED_PARAMS = %i[local remote limit only_media grouped_admin_statuses exclude_direct_statuses exclude_replies domain].freeze

          def show
            cache_if_unauthenticated!
            @statuses = load_statuses
            @patchwork_post_reactions = build_patchwork_post_reactions(@statuses)

            render json: @statuses,
                   each_serializer: REST::StatusSerializer,
                   relationships: StatusRelationshipsPresenter.new(@statuses, current_user&.account_id),
                   include_patchwork_post_reactions: true,
                   patchwork_post_reactions: @patchwork_post_reactions
          end

          private

          def load_statuses
            preloaded_for_you_statuses_page
          end

          def preloaded_for_you_statuses_page
            preload_collection(for_you_statuses, Status)
          end

          def for_you_statuses
            limit = limit_param(DEFAULT_STATUSES_LIMIT)

            home_like = if include_home_statuses?
                          PatchworkExtensions::ForYouFeed.new(
                            current_account,
                            grouped_admin_statuses: truthy_param?(:grouped_admin_statuses),
                            exclude_direct_statuses: truthy_param?(:exclude_direct_statuses),
                            exclude_replies: truthy_param?(:exclude_replies)
                          ).get(
                            expanded_limit(limit),
                            params[:max_id],
                            params[:since_id],
                            params[:min_id]
                          )
                        else
                          []
                        end

            relay_statuses = selected_domains.flat_map do |domain|
              NewsmastMastodon::RelayFeed.new(
                domain,
                current_account,
                only_media: truthy_param?(:only_media)
              ).get(
                expanded_limit(limit),
                params[:max_id],
                params[:since_id],
                params[:min_id]
              )
            end

            status_ids = (home_like.map(&:id) + relay_statuses.map(&:id)).uniq.sort.reverse.first(limit)
            return [] if status_ids.empty?

            scope = Status.where(id: status_ids).joins(:account).merge(Account.without_suspended.without_silenced)
            scope = scope.not_excluded_by_account(current_account)
            scope = scope.joins(:media_attachments).group(:id) if truthy_param?(:only_media)

            records = scope.index_by(&:id)
            status_ids.filter_map { |id| records[id] }
          end

          def requested_domains
            @requested_domains ||= begin
              raw = params[:domain]

              Array(raw)
                .flat_map { |value| value.to_s.split(",") }
                .map { |value| value.strip.downcase }
                .reject(&:blank?)
                .uniq
            end
          end

          def configured_domains
            @configured_domains ||= NewsmastMastodon::CustomRelayConfig.domains
          end

          def enabled_domains
            @enabled_domains ||= begin
              inbox_urls = configured_domains.map { |domain| NewsmastMastodon::CustomRelayConfig.inbox_url_for(domain) }
              Relay.enabled.where(inbox_url: inbox_urls).pluck(:inbox_url).filter_map do |url|
                NewsmastMastodon::CustomRelayConfig.domain_from_inbox_url(url)
              end
            end
          end

          def selected_domains
            return [] if requested_domains.empty?

            requested_domains & enabled_domains
          end

          def include_home_statuses?
            return true if requested_domains.empty?
            return true if local_domain.blank?

            requested_domains.include?(local_domain.downcase)
          end

          def local_domain
            ENV.fetch("LOCAL_DOMAIN", nil)
          end

          def validate_requested_domains!
            allowed_domains = configured_domains.dup
            allowed_domains << local_domain.downcase if local_domain.present?

            unknown = requested_domains - allowed_domains
            return if unknown.empty?

            render json: { error: I18n.t("api.errors.unknown_relay_domains", domains: unknown.join(", ")) }, status: :bad_request
          end

          def expanded_limit(limit)
            [limit * 3, 120].min
          end

          def next_path
            api_v1_timelines_for_you_custom_timeline_url next_path_params
          end

          def prev_path
            api_v1_timelines_for_you_custom_timeline_url prev_path_params
          end
        end
      end
    end
  end
end
