# frozen_string_literal: true

module PatchworkExtensions
  # MEDIA-01: background alt-text generation for uploaded media.
  # Extracted from NewsmastMastodon::GenerateAltTextWorker; queue, retry and
  # dead-job options are unchanged. Gem A keeps its own worker class so jobs
  # queued before the cutover still deserialize (INFRA-05).
  class GenerateAltTextWorker
    include Sidekiq::Worker
    sidekiq_options queue: "default", retry: 2, dead: false, retry_in: ->(_count) { 24.hours }

    def perform(media_attachment_id)
      @media_attachment = MediaAttachment.find(media_attachment_id)
      if @media_attachment.present?
        PatchworkExtensions::AfterUploadImageService.new(@media_attachment.id).call if @media_attachment.can_generate_alt?
      end
    end
  end
end
