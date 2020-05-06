use Rack::Runtime
use Rack::ContentLength
use Rack::ContentType
use Rack::Head
use Rack::Deflater
run Fawn::Server::StaticFile
