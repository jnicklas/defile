require "json"
require "sinatra/base"
require "tempfile"

module Refile
  # A Rack application which can be mounted or run on its own.
  #
  # @example mounted in Rails
  #   Rails.application.routes.draw do
  #     mount Refile::App.new, at: "attachments", as: :refile_app
  #   end
  #
  # @example as standalone app
  #   require "refile"
  #
  #   run Refile::App.new
  class App < Sinatra::Base
    configure do
      set :show_exceptions, false
      set :raise_errors, false
      set :sessions, false
      set :logging, false
      set :dump_errors, false
      use CustomLogger, "Refile::App", proc { Refile.logger }
    end

    before do
      if Refile.allow_origin
        response["Access-Control-Allow-Origin"] = Refile.allow_origin
        response["Access-Control-Allow-Headers"] = request.env["HTTP_ACCESS_CONTROL_REQUEST_HEADERS"].to_s
        response["Access-Control-Allow-Method"] = request.env["HTTP_ACCESS_CONTROL_REQUEST_METHOD"].to_s
      end
    end

    get "/:token/:backend/:id/:filename" do
      add_cache_headers
      halt if request.head?
      stream_file file.download
    end

    get "/:token/:backend/:processor/:id/:file_basename.:extension" do
      add_cache_headers
      halt if request.head?
      stream_file processor.call(file.download, format: params[:extension])
    end

    get "/:token/:backend/:processor/:id/:filename" do
      add_cache_headers
      halt if request.head?
      stream_file processor.call(file.download)
    end

    get "/:token/:backend/:processor/*/:id/:file_basename.:extension" do
      add_cache_headers
      halt if request.head?
      stream_file processor.call(file.download, *params[:splat].first.split("/"), format: params[:extension])
    end

    get "/:token/:backend/:processor/*/:id/:filename" do
      add_cache_headers
      halt if request.head?
      stream_file processor.call(file.download, *params[:splat].first.split("/"))
    end

    options "/:backend" do
      ""
    end

    post "/:backend" do
      halt 404 unless Refile.direct_upload.include?(params[:backend])
      tempfile = request.params.fetch("file").fetch(:tempfile)
      file = backend.upload(tempfile)
      content_type :json
      { id: file.id }.to_json
    end

    not_found do
      content_type :text
      "not found"
    end

    error 403 do
      content_type :text
      "forbidden"
    end

    error do |error_thrown|
      log_error("Error -> #{error_thrown}")
      error_thrown.backtrace.each do |line|
        log_error(line)
      end
      content_type :text
      "error"
    end

  private

    def logger
      Refile.logger
    end

    def add_cache_headers
      expires Refile.content_max_age, :public, :must_revalidate
      etag file.etag
      last_modified file.last_modified
    end

    def stream_file(file)
      halt 403 unless verified?

      if file.respond_to?(:path)
        path = file.path
      else
        path = Dir::Tmpname.create(params[:id]) {}
        IO.copy_stream file, path
      end

      filename = request.path.split("/").last

      send_file path, filename: filename, disposition: "inline", type: ::File.extname(request.path)
    end

    def backend
      Refile.backends.fetch(params[:backend]) do |name|
        log_error("Could not find backend: #{name}")
        halt 404
      end
    end

    def file
      file = backend.get(params[:id])
      unless file.exists?
        log_error("Could not find attachment by id: #{params[:id]}")
        halt 404
      end
      file
    end

    def processor
      Refile.processors.fetch(params[:processor]) do |name|
        log_error("Could not find processor: #{name}")
        halt 404
      end
    end

    def log_error(message)
      logger.error "#{self.class.name}: #{message}"
    end

    def verified?
      base_path = request.path.gsub(::File.join(request.script_name, params[:token]), "")

      Refile.valid_token?(base_path, params[:token])
    end
  end
end
