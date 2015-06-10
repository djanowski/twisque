require "./app"

use Rack::Session::Cookie,
  secret: ENV.fetch("SESSION_SECRET"),
  secure: ENV.fetch("RACK_ENV") == "production"

run Web
