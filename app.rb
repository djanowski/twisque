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

  def enqueue_tweet(text:, delay:)
    job = {
      text:        text,
      screen_name: session.fetch(:screen_name),

      oauth_token:        session.fetch(:oauth_token),
      oauth_token_secret: session.fetch(:oauth_secret),
    }

    id = $disque.push("tweets", job.to_json, 0, delay: delay, retry: 30)

    session[:notice] = sprintf("Done! Your tweet will be published in approximately %s seconds.", delay)

    session[:jobs] ||= []
    session[:jobs] << id
  end

  def redirect_to_twitter
    response = $twitter.request(
      "POST", "/oauth/request_token",
      body: { oauth_callback: URI.join(req.url, "/callback").to_s }
    )
    response = Rack::Utils.parse_query(response.body)

    session[:oauth_token]  = response.fetch("oauth_token")
    session[:oauth_secret] = response.fetch("oauth_token_secret")

    query = Rack::Utils.build_query(oauth_token: response.fetch("oauth_token"))

    res.redirect(sprintf("https://api.twitter.com/oauth/authenticate?%s", query))
  end
end

Web = Syro.new(WebDeck) do
  res["Content-Security-Policy"]           = "default-src 'self' style-src 'self' 'unsafe-inline'"
  res["Strict-Transport-Security"]         = "max-age=63072000; includeSubdomains; preload"
  res["X-Content-Type-Options"]            = "nosniff"
  res["X-Download-Options"]                = "noopen"
  res["X-Frame-Options"]                   = "deny"
  res["X-Permitted-Cross-Domain-Policies"] = "none"
  res["X-XSS-Protection"]                  = "1; mode=block"

  post {
    tweet = {
      text:  req.POST["text"],
      delay: Integer(req.POST["delay"])
    }

    if session[:user_id]
      enqueue_tweet(tweet)
      res.redirect("/")
    else
      session[:tweet] = tweet
      redirect_to_twitter
    end
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

        tweet = session[:tweet]

        session.clear
        session[:oauth_token]  = response.fetch("oauth_token")
        session[:oauth_secret] = response.fetch("oauth_token_secret")
        session[:user_id]      = response.fetch("user_id")
        session[:screen_name]  = response.fetch("screen_name")

        if tweet
          enqueue_tweet(tweet)
        end

        res.redirect("/")
      rescue Client::Error
        res.redirect("/login")
      end
    }
  }

  on("login") {
    get {
      session.clear
      redirect_to_twitter
    }
  }

  on("logout") {
    get {
      session.clear
      res.redirect("/")
    }
  }

  get {
    jobs = []

    session[:jobs].dup.each do |id|
      job = Hash[*$disque.call("SHOW", id)]

      if job.empty?
        session[:jobs].delete(id)
      else
      puts job.fetch("state")
        text = JSON.parse(job.fetch("body")).fetch("text")

        date = Time.at(job.fetch("ctime") / 1_000_000_000) + job.fetch("delay")

        jobs << { text: text, date: date.utc }
      end
    end if session[:jobs]

    jobs = jobs.sort_by { |j| j.fetch(:date) }

    render("index", jobs: jobs)
  }
end
