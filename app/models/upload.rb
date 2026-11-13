# frozen_string_literal: true

class Upload < ApplicationRecord
  extend Memoist

  class Error < StandardError; end

  # The list of allowed archive file types.
  ARCHIVE_FILE_TYPES = %i[zip rar 7z]

  # The maximum number of files allowed per upload. If you change this, you should also change `RACK_MULTIPART_FILE_LIMIT` in config/puma.rb.
  MAX_FILES_PER_UPLOAD = 100

  # The maximum number of 'pending' or 'processing' media assets a single user can have at once.
  MAX_QUEUED_ASSETS = 250

  attr_accessor :files

  belongs_to :uploader, class_name: "User"
  has_many :upload_media_assets, dependent: :destroy
  has_many :media_assets, through: :upload_media_assets
  has_many :posts, through: :media_assets

  # Decode percent-encoded Unicode characters in the URL
  normalizes :source, with: ->(url) { Danbooru::URL.parse(url)&.to_normalized_s.presence || url }

  validate :validate_source, if: -> { source.present? && source_changed? }
  validates :referer_url, format: { with: %r{\Ahttps?://}i, message: "is not a valid URL" }, length: { maximum: 2000 }, if: -> { referer_url.present? && referer_url_changed? }
  validates :status, inclusion: { in: %w[pending processing completed error] }
  validate :validate_file_and_source, on: :create
  validate :validate_archive_files, on: :create
  validate :validate_uploader_is_not_limited, on: :create

  after_create :async_process_upload!

  scope :pending, -> { where(status: "pending") }
  scope :processing, -> { where(status: "processing") }
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "error") }
  scope :expired, -> { processing.where(created_at: ..4.hours.ago) }

  def self.visible(user)
    if user.is_moderator?
      all
    else
      where(uploader: user)
    end
  end

  def self.prune!
    expired.update_all(status: "error", error: "Stuck processing for more than 4 hours")
  end

  concerning :StatusMethods do
    def is_pending?
      status == "pending"
    end

    def is_processing?
      status == "processing"
    end

    def is_completed?
      status == "completed"
    end

    def is_errored?
      status == "error"
    end

    def is_finished?
      is_completed? || is_errored?
    end
  end

  concerning :ValidationMethods do
    def validate_source
      if source.length > 2000
        errors.add(:source, I18n.t("upload.source_too_long"))
      elsif !source.match?(%r{\Ahttps?://}i) || Danbooru::URL.parse(source).nil?
        errors.add(:source, I18n.t("upload.source_invalid_url"))
      end
    end

    def validate_file_and_source
      if files.present? && source.present?
        errors.add(:base, I18n.t("upload.file_and_source"))
      elsif files.blank? && source.blank?
        errors.add(:base, I18n.t("upload.no_file_or_source"))
      end
    end

    def validate_uploader_is_not_limited
      queued_asset_count = uploader.upload_media_assets.unfinished.count

      if queued_asset_count > MAX_QUEUED_ASSETS
        errors.add(:base, I18n.t("upload.too_many_queued", queued_asset_count: queued_asset_count, max_queued_assets: MAX_QUEUED_ASSETS))
      end
    end

    def validate_archive_files
      return unless files.present?

      archive_files.each do |archive, filename|
        if !archive.file_ext.in?(ARCHIVE_FILE_TYPES)
          errors.add(:base, I18n.t("upload.unsupported_file_type", filename: filename))
        elsif archive.exists? { |_, count| count > MAX_FILES_PER_UPLOAD }
          # XXX Potential zip bomb containing thousands of files; don't process it any further.
          errors.add(:base, I18n.t("upload.too_many_files_in_archive", filename: filename, max_files_per_upload: MAX_FILES_PER_UPLOAD))
          next
        elsif archive.uncompressed_size > MediaAsset::MAX_FILE_SIZE
          errors.add(:base, I18n.t("upload.archive_too_large", filename: filename, archive_uncompressed_size: archive.uncompressed_size.to_fs(:human_size), MediaAsset: MediaAsset::MAX_FILE_SIZE.to_fs(:human_size)))
        elsif (entry = archive.entries.find { |entry| entry.pathname.starts_with?("/") })
          errors.add(:base, I18n.t("upload.invalid_archive_path", entry_pathname_utf8: entry.pathname_utf8, filename: filename))
        elsif (entry = archive.entries.find { |entry| entry.directory_traversal? })
          errors.add(:base, "'#{entry.pathname_utf8}' in '#{filename}' can't contain '..' components")
        elsif (entry = archive.entries.find { |entry| !entry.file? && !entry.directory? })
          errors.add(:base, I18n.t("upload.non_regular_file", entry_pathname_utf8: entry.pathname_utf8, filename: filename))
        end
      end

      total_files = archive_files.map(&:first).sum(&:file_count) + (files.size - archive_files.size)
      if total_files > MAX_FILES_PER_UPLOAD
        errors.add(:base, I18n.t("upload.too_many_files", max_files_per_upload: MAX_FILES_PER_UPLOAD, total_files: total_files))
      end
    end
  end

  def self.ai_tags_match(tag_string, current_user:, score_range: (50..))
    upload_media_assets = MediaAssetQuery.search(tag_string, relation: UploadMediaAsset.joins(:media_asset), foreign_key: :media_asset_id, score_range: score_range, current_user: current_user)
    where(upload_media_assets.where("upload_media_assets.upload_id = uploads.id").arel.exists)
  end

  def self.any_source_matches(source)
    upload_media_assets = UploadMediaAsset.where_ilike(:source_url, source)
    q = where_ilike(:source, source)
    q = q.or(where_ilike(:referer_url, source))
    q = q.or(where(upload_media_assets.where("upload_media_assets.upload_id = uploads.id").arel.exists))
    q
  end

  def self.search(params, current_user)
    q = search_attributes(params, %i[id created_at updated_at source referer_url status media_asset_count uploader upload_media_assets media_assets posts], current_user: current_user)

    if params[:ai_tags_match].present?
      min_score = params.fetch(:min_score, 50).to_i
      q = q.ai_tags_match(params[:ai_tags_match], score_range: (min_score..), current_user: current_user)
    end

    if params[:is_posted].to_s.truthy?
      q = q.where.not(id: Upload.where.missing(:posts))
    elsif params[:is_posted].to_s.falsy?
      q = q.where(id: Upload.where.missing(:posts))
    end

    if params[:any_source_matches].present?
      q = q.any_source_matches(params[:any_source_matches])
    end

    case params[:order]
    when "id", "id_desc"
      q = q.order(id: :desc)
    when "id_asc"
      q = q.order(id: :asc)
    when "random"
      q = q.order("random()")
    else
      q = q.apply_default_order(params)
    end

    q
  end

  def async_process_upload!
    if files.present?
      process_upload!
    elsif source.present?
      ProcessUploadJob.perform_later(self)
    else
      raise "No file or source given" # Should never happen
    end
  end

  def process_upload!
    update!(status: "processing")

    if files.present?
      process_file_upload!
    elsif source.present?
      process_source_upload!
    else
      raise Error, "No file or source given" # Should never happen
    end
  rescue Exception => e
    update!(status: "error", error: e.message)
  end

  def process_source_upload!
    page_url = source_extractor.page_url
    image_urls = source_extractor.image_urls

    if image_urls.empty?
      raise Error, "#{source} doesn't contain any images"
    end

    upload_media_assets = image_urls.map do |image_url|
      UploadMediaAsset.new(upload: self, source_url: image_url, page_url: page_url, media_asset: nil)
    end

    transaction do
      update!(media_asset_count: upload_media_assets.size)
      upload_media_assets.each(&:save!)
    end
  end

  def process_file_upload!
    tmpdirs = []

    upload_media_assets = uploaded_files.flat_map do |file, original_filename|
      if file.is_a?(Danbooru::Archive)
        tmpdir, filenames = file.extract!
        tmpdirs << tmpdir

        Danbooru.natural_sort(filenames).map do |filename|
          name = "file://#{original_filename}/#{Pathname.new(filename).relative_path_from(tmpdir)}" # "file://foo.zip/foo/1.jpg"
          UploadMediaAsset.new(upload: self, file: filename, source_url: name)
        end
      else
        UploadMediaAsset.new(upload: self, file: file, source_url: "file://#{original_filename}")
      end
    end

    transaction do
      update!(media_asset_count: upload_media_assets.size)
      upload_media_assets.each(&:save!)
    end
  ensure
    tmpdirs.each { |tmpdir| FileUtils.rm_rf(tmpdir) }
  end

  # The list of files uploaded from disk, with their filenames.
  def uploaded_files
    files.map do |_index, file|
      if FileTypeDetector.new(file.tempfile).file_ext.in?(ARCHIVE_FILE_TYPES)
        [Danbooru::Archive.open!(file.tempfile), file.original_filename]
      else
        [MediaFile.open(file.tempfile), file.original_filename]
      end
    end
  end

  # The list of archive files uploaded from disk, with their filenames.
  def archive_files
    uploaded_files.select do |file, _original_filename|
      file.is_a?(Danbooru::Archive)
    end
  end

  def source_extractor
    return nil if source.blank?
    Source::Extractor.find(source, referer_url)
  end

  def self.available_includes
    [:uploader, :upload_media_assets, :media_assets, :posts]
  end

  memoize :source_extractor, :archive_files, :uploaded_files
end
