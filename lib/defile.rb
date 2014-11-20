require "fileutils"

module Defile
  class << self
    attr_accessor :read_chunk_size

    def configure
      yield self
    end

    def verify_uploadable(uploadable)
      [:size, :read, :eof?, :close].each do |m|
        unless uploadable.respond_to?(m)
          raise ArgumentError, "does not respond to `#{m}`."
        end
      end
      true
    end
  end

  require "defile/version"
  require "defile/random_hasher"
  require "defile/file"
  require "defile/backend/file_system"
end

Defile.configure do |config|
  # FIXME: what is a sane default here? This is a little less than a
  # memory page, which seemed like a good default, is there a better
  # one?
  config.read_chunk_size = 3000
end