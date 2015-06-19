require_relative "../app"

loop do

  begin
    $disque.fetch(from: ["tweets"]) do |body|
      job = JSON.parse(body)

      res = $twitter.request(
        "POST", "/1.1/statuses/update.json",
        body:  { status: job.fetch("text") },
        oauth: {
          token:        job.fetch("oauth_token"),
          token_secret: job.fetch("oauth_token_secret"),
        }
      )

      id = JSON.parse(res.body).fetch("id")

      $twitter.request(
        "POST", "/1.1/favorites/create.json",
        body:  { id: id },
        oauth: {
          token:        ENV.fetch("TWITTER_TOKEN"),
          token_secret: ENV.fetch("TWITTER_TOKEN_SECRET")
        }
      )

      printf("%s Processed tweet for %s\n", Time.now.iso8601, job.fetch("screen_name"))
    end
  rescue => e
    $stderr.printf("%s Error processing job: %s: %s\n", Time.now.iso8601, e.class, e.message)
  end
end
