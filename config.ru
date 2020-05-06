use Rack::Runtime
use Rack::ContentLength
use Rack::ContentType
use Rack::Head
run Fawn::Rack::StaticFile
