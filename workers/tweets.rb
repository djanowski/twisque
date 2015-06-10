require_relative "../app"

loop do

  begin
    $disque.fetch(from: ["tweets"]) do |body|
      job = JSON.parse(body)

      $twitter.request(
        "POST", "/1.1/statuses/update.json",
        body:  { status: job.fetch("text") },
        oauth: {
          token:        job.fetch("oauth_token"),
          token_secret: job.fetch("oauth_token_secret"),
        }
      )

      printf("%s Processed tweet for %s\n", Time.now.iso8601, job.fetch("screen_name"))
    end
  rescue => e
    $stderr.printf("%s Error processing job: %s: %s\n", Time.now.iso8601, e.class, e.message)
  end
end
