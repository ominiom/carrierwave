# encoding: utf-8

module CarrierWave

  class FormNotMultipart < UploadError
    def message
      "You tried to assign a String or a Pathname to an uploader, for security reasons, this is not allowed.\n\n If this is a file upload, please check that your upload form is multipart encoded."
    end
  end

  ##
  # Generates a unique cache id for use in the caching system
  #
  # === Returns
  #
  # [String] a cache id in the format YYYYMMDD-HHMM-PID-RND
  #
  def self.generate_cache_id
    Time.now.strftime('%Y%m%d-%H%M') + '-' + Process.pid.to_s + '-' + ("%04d" % rand(9999))
  end

  module Uploader
    module Cache
      extend ActiveSupport::Concern

      include CarrierWave::Uploader::Callbacks
      include CarrierWave::Uploader::Configuration

      ##
      # Returns true if the uploader has been cached
      #
      # === Returns
      #
      # [Bool] whether the current file is cached
      #
      def cached?
        @cache_id
      end

      ##
      # Caches the remotely stored file
      #
      # This is useful when about to process images. Most processing solutions
      # require the file to be stored on the local filesystem.
      #
      def cache_stored_file!
        _content = file.read
        if _content.is_a?(File) # could be if storage is Fog
          sanitized = CarrierWave::Storage::Fog.new(self).retrieve!(File.basename(_content.path))
          sanitized.read if sanitized.exists?

        else
          sanitized = SanitizedFile.new :tempfile => StringIO.new(file.read),
            :filename => File.basename(path), :content_type => file.content_type
        end

        cache! sanitized
      end

      ##
      # Returns a String which uniquely identifies the currently cached file for later retrieval
      #
      # === Returns
      #
      # [String] a cache name, in the format YYYYMMDD-HHMM-PID-RND/filename.txt
      #
      def cache_name
        File.join(cache_id, full_original_filename) if cache_id and original_filename
      end

      ##
      # Caches the given file. Calls process! to trigger any process callbacks.
      #
      # By default, cache!() uses copy_to(), which operates by copying the file
      # to the cache, then deleting the original file.  If move_to_cache() is
      # overriden to return true, then cache!() uses move_to(), which simply
      # moves the file to the cache.  Useful for large files.
      #
      # === Parameters
      #
      # [new_file (File, IOString, Tempfile)] any kind of file object
      #
      # === Raises
      #
      # [CarrierWave::FormNotMultipart] if the assigned parameter is a string
      #
      def cache!(new_file)
        new_file = CarrierWave::SanitizedFile.new(new_file)

        unless new_file.empty?
          raise CarrierWave::FormNotMultipart if new_file.is_path? && ensure_multipart_form

          with_callbacks(:cache, new_file) do
            self.cache_id = CarrierWave.generate_cache_id unless cache_id

            @filename = new_file.filename
            self.original_filename = new_file.filename

            if cacher
              cacher.cache!(cache_name, new_file.read) 
            else
              if move_to_cache
                @file = new_file.move_to(cache_path, permissions, directory_permissions)
              else
                @file = new_file.copy_to(cache_path, permissions, directory_permissions)
              end
            end
          end
        end
      end

      ##
      # Retrieves the file with the given cache_name from the cache.
      #
      # === Parameters
      #
      # [cache_name (String)] uniquely identifies a cache file
      #
      # === Raises
      #
      # [CarrierWave::InvalidParameter] if the cache_name is incorrectly formatted.
      #
      def retrieve_from_cache!(cache_name)
        with_callbacks(:retrieve_from_cache, cache_name) do
          self.cache_id, self.original_filename = cache_name.to_s.split('/', 2)

          @filename = original_filename

          if cacher
            # Cache directory may not even exist
            FileUtils.mkdir_p(File.dirname(cache_path))

            File.open(cache_path, 'wb') do |file|
              file.write cacher.retrieve_from_cache!(cache_name)
            end
          end
          
          @file = CarrierWave::SanitizedFile.new(cache_path)
        end
      end

    private

      def cache_path
        File.expand_path(File.join(cache_dir, cache_name), root)
      end

      attr_reader :cache_id, :original_filename

      # We can override the full_original_filename method in other modules
      alias_method :full_original_filename, :original_filename

      def cache_id=(cache_id)
        raise CarrierWave::InvalidParameter, "invalid cache id" unless cache_id =~ /\A[\d]{8}\-[\d]{4}\-[\d]+\-[\d]{4}\z/
        @cache_id = cache_id
      end

      def original_filename=(filename)
        raise CarrierWave::InvalidParameter, "invalid filename" if filename =~ CarrierWave::SanitizedFile.sanitize_regexp
        @original_filename = filename
      end

    end # Cache
  end # Uploader
end # CarrierWave
