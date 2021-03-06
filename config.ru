require "./app"

use Rack::Session::Cookie,
  secret: ENV.fetch("SESSION_SECRET"),
  secure: HTTPS_ENABLED

run Web
