require "./app"

use Rack::Session::Cookie, secret: ENV.fetch("SESSION_SECRET")

run Web
