module Refile
  # @api private
  class Attacher
    attr_reader :definition, :record, :errors
    attr_accessor :remove

    Presence = ->(val) { val if val != "" }

    def initialize(definition, record)
      @definition = definition
      @record = record
      @errors = []
      @metadata = {}
    end

    def name
      @definition.name
    end

    def cache
      @definition.cache
    end

    def store
      @definition.store
    end

    def id
      Presence[read(:id)]
    end

    def size
      Presence[@metadata[:size] || read(:size)]
    end

    def filename
      Presence[@metadata[:filename] || read(:filename)]
    end

    def content_type
      Presence[@metadata[:content_type] || read(:content_type)]
    end

    def cache_id
      Presence[@metadata[:id]]
    end

    def basename
      if filename and extension
        ::File.basename(filename, "." << extension)
      else
        filename
      end
    end

    def extension
      if filename
        Presence[::File.extname(filename).sub(/^\./, "")]
      elsif content_type
        type = MIME::Types[content_type][0]
        type.extensions[0] if type
      end
    end

    def get
      if cache_id
        cache.get(cache_id)
      elsif id
        store.get(id)
      end
    end

    def set(value)
      if value.is_a?(String)
        retrieve!(value)
      else
        cache!(value)
      end
    end

    def retrieve!(value)
      @metadata = JSON.parse(value, symbolize_names: true) || {}
      write_metadata if cache_id
    rescue JSON::ParserError
    end

    def cache!(uploadable)
      @metadata = {
        size: uploadable.size,
        content_type: Refile.extract_content_type(uploadable),
        filename: Refile.extract_filename(uploadable)
      }
      if valid?
        @metadata[:id] = cache.upload(uploadable).id
        write_metadata
      elsif @definition.raise_errors?
        raise Refile::Invalid, @errors.join(", ")
      end
    end

    def download(url)
      unless url.to_s.empty?
        response = RestClient::Request.new(method: :get, url: url, raw_response: true).execute
        @metadata = {
          size: response.file.size,
          filename: ::File.basename(url),
          content_type: response.headers[:content_type]
        }
        if valid?
          @metadata[:id] = cache.upload(response.file).id
          write_metadata
        elsif @definition.raise_errors?
          raise Refile::Invalid, @errors.join(", ")
        end
      end
    rescue RestClient::Exception
      @errors = [:download_failed]
      raise if @definition.raise_errors?
    end

    def store!
      if remove?
        delete!
        write(:id, nil)
      elsif cache_id
        file = store.upload(get)
        delete!
        write(:id, file.id)
      end
      write_metadata
      @metadata = {}
    end

    def delete!
      cache.delete(cache_id) if cache_id
      store.delete(id) if id
      @metadata = {}
    end

    def remove?
      remove and remove != "" and remove !~ /\A0|false$\z/
    end

    def present?
      not @metadata.empty?
    end

    def data
      @metadata if valid?
    end

    def valid?
      @errors = @definition.validate(self)
      @errors.empty?
    end

  private

    def read(column)
      m = "#{name}_#{column}"
      value ||= record.send(m) if record.respond_to?(m)
      value
    end

    def write(column, value)
      m = "#{name}_#{column}="
      record.send(m, value) if record.respond_to?(m) and not record.frozen?
    end

    def write_metadata
      write(:size, size)
      write(:content_type, content_type)
      write(:filename, filename)
    end
  end
end
