# frozen_string_literal: true

# Engine API routes for Gem B features.
PatchworkExtensions::Engine.routes.draw do
  # UI-03: Mobile App Association Endpoints (extracted from newsmast_mastodon).
  # Public well-known routes (no auth required).
  scope path: ".well-known" do
    get "apple-app-site-association", to: "well_known/deep_links#apple_app_site_association",
        as: :apple_app_site_association
    get "assetlinks.json", to: "well_known/deep_links#asset_links",
        as: :asset_links
  end

  namespace :api, defaults: { format: "json" } do
    namespace :v1 do
      # COMMUNITY-03: Starter-Pack Discovery (extracted from newsmast_mastodon)
      resources :channels, only: [] do
        collection do
          get :starter_packs_channels
        end
        member do
          get :starter_packs_detail
        end
      end

      # CONV-01: Conversation Lookup and Read State (extracted from newsmast_mastodon)
      namespace :patchwork do
        resources :conversations, only: [] do
          collection do
            get  :check_conversation
            post :read_all
          end
        end

        # AUTH-06: Account Deletion (extracted from newsmast_mastodon)
        resources :account_deletion, only: [ :destroy ]
      end

      # FEED-02: For You and Mixed Channel Timeline (extracted from newsmast_mastodon)
      namespace :timelines do
        get "for_you_custom_timeline", to: "for_you_custom_timeline#show", as: :for_you_custom_timeline
      end

      # BOOST-01: Custom Boost-Bot Status Operations (extracted from newsmast_mastodon)
      namespace :custom_statuses do
        post "add_custom_boost_bot_status",    to: "custom_boost_bot_status#add_custom_boost_bot_status",    as: :add_custom_boost_bot_status
        post "remove_custom_boost_bot_status", to: "custom_boost_bot_status#remove_custom_boost_bot_status", as: :remove_custom_boost_bot_status
      end

      # MEDIA-02: Link Previews (extracted from newsmast_mastodon)
      resources :utilities, only: [] do
        collection do
          get :link_preview
        end
      end

      # AUTH-06: Account Deletion and Locale Preferences (extracted from newsmast_mastodon)
      post "/delete_account", to: "accounts#delete_account"
      resources :user_locales, only: [ :create ]

      # CMS-02: Ghost Newsletter Subscription (extracted from newsmast_mastodon)
      namespace :accounts do
        post "subscribe_leicester", to: "ghost_subscriptions#manage_subscription"
      end
    end
  end
end
