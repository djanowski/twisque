require "syro"
require "twitter"
require "hmote"
require "disque"

require_relative "lib/client"

$disque = Disque.new(ENV.fetch("TYND_DISQUE_NODES"), auth: ENV.fetch("TYND_DISQUE_AUTH"))

$twitter = Client.new(
  key:      ENV.fetch("TWITTER_KEY"),
  secret:   ENV.fetch("TWITTER_SECRET"),
  endpoint: "https://api.twitter.com/"
)

class WebDeck < Syro::Deck
  include HMote::Helpers

  def render(template, params = {}, layout = "layout")
    res.headers["Content-Type"] ||= "text/html; charset=utf-8"
    res.write(view(template, params, layout))
  end

  def view(template, params = {}, layout = "layout")
    return partial(layout, params.merge(content: partial(template, params)))
  end

  def partial(template, params = {})
    return hmote(template_path(template), params.merge(app: self), TOPLEVEL_BINDING)
  end

  def template_path(template)
    if template.end_with?(".mote")
      return template
    else
      return File.join("views", "#{template}.mote")
    end
  end

  def session
    env["rack.session"]
  end
end

Web = Syro.new(WebDeck) do
  post {
    delay = Integer(req.POST["delay"])

    job = {
      text:        req.POST["text"],
      screen_name: session.fetch(:screen_name),

      oauth_token:        session.fetch(:oauth_token),
      oauth_token_secret: session.fetch(:oauth_secret),
    }

    $disque.push("tweets", job.to_json, 0, delay: delay, retry: 30)

    res.redirect("/")
  }

  on("callback") {
    get {
      token    = req.GET["oauth_token"]
      verifier = req.GET["oauth_verifier"]

      token_secret = session.fetch(:oauth_secret)

      begin
        response = $twitter.request(
          "POST", "/oauth/access_token",
          body:  { oauth_verifier: verifier },
          oauth: { token: token, token_secret: token_secret }
        )
        response = Rack::Utils.parse_query(response.body)

        session.clear
        session[:oauth_token]  = response.fetch("oauth_token")
        session[:oauth_secret] = response.fetch("oauth_token_secret")
        session[:user_id]      = response.fetch("user_id")
        session[:screen_name]  = response.fetch("screen_name")

        res.redirect("/")
      rescue Client::Error
        res.redirect("/login")
      end
    }
  }

  on("login") {
    get {
      response = $twitter.request(
        "POST", "/oauth/request_token",
        body: { oauth_callback: URI.join(req.url, "/callback").to_s }
      )
      response = Rack::Utils.parse_query(response.body)

      session.clear
      session[:oauth_token]  = response.fetch("oauth_token")
      session[:oauth_secret] = response.fetch("oauth_token_secret")

      res.redirect("https://api.twitter.com/oauth/authenticate?" + Rack::Utils.build_query(oauth_token: response.fetch("oauth_token")))
    }
  }

  get {
    render("index")
  }
end
