require "json"

class Tweets
  def call(body)
    job = JSON.parse(body)

    # Become friends in order to send notifications
    # about the scheduled tweet status.
    friend(job)

    begin
      res = $twitter.request(
        "POST", "/1.1/statuses/update.json",
        body:  { status: job.fetch("text") },
        oauth: {
          token:        job.fetch("oauth_token"),
          token_secret: job.fetch("oauth_token_secret"),
        }
      )
    rescue Client::Error => e
      error = JSON.parse(e.response.body).fetch("errors")[0]

      $twitter.request(
        "POST", "/1.1/direct_messages/new.json",
        body:  { screen_name: job.fetch("screen_name"), text: "Error: " + error.fetch("message") },
        oauth: {
          token:        ENV.fetch("TWITTER_TOKEN"),
          token_secret: ENV.fetch("TWITTER_TOKEN_SECRET")
        }
      )

      return
    end

    id = JSON.parse(res.body).fetch("id")

    begin
      $twitter.request(
        "POST", "/1.1/favorites/create.json",
        body:  { id: id },
        oauth: {
          token:        ENV.fetch("TWITTER_TOKEN"),
          token_secret: ENV.fetch("TWITTER_TOKEN_SECRET")
        }
      )
    rescue Client::Error => e
      $stderr.printf("%s Error favoriting tweet %s: %s\n", Time.now.iso8601, id, e.message)
    end

    printf("%s Processed tweet for %s\n", Time.now.iso8601, job.fetch("screen_name"))
  end

  def friend(job)
    begin
      $twitter.request(
        "POST", "/1.1/friendships/create.json",
        body:  { screen_name: "twisque" },
        oauth: {
          token:        job.fetch("oauth_token"),
          token_secret: job.fetch("oauth_token_secret"),
        }
      )
    rescue Client::Error => e
    end

    begin
      $twitter.request(
        "POST", "/1.1/friendships/create.json",
        body:  { screen_name: job.fetch("screen_name") },
        oauth: {
          token:        ENV.fetch("TWITTER_TOKEN"),
          token_secret: ENV.fetch("TWITTER_TOKEN_SECRET")
        }
      )
    rescue Client::Error => e
    end
  end
end
