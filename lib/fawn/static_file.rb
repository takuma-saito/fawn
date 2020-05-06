require 'stringio'
require_relative 'const'

module Fawn
  module Rack
    class StaticFile
      include Fawn::Const
      BASE_DIR = './dist'.freeze
      MIME =
        {
          jpg: 'image/jpg',
          jpeg: 'image/jpg',
          ico: 'image/webp',
          png: 'image/png',
          gif: 'image/gif',
          html: 'text/html',
          css: 'text/css',
          js: 'application/js',
        }
      def self.call(env)
        headers = {}
        response =
          if File.readable?(filename = "#{BASE_DIR}#{env[SCRIPT_NAME]}") && File.file?(filename)
            {
              status: 200,
              body: (body = File.read(filename)),
              content_type: "#{MIME[filename.split(".").last.to_sym] || 'application/octet-stream'}; charset=#{body.encoding}"
            }
          else
            {
              status: 404,
              body: 'File not found',
              content_type: 'text/plain; charset=utf-8',
            }
          end
        headers['Date'] = DateTime.now.rfc822
        [response[:status], headers, StringIO.new(body)]
      end
    end
  end
end