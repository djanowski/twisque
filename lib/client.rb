require "net/http/persistent"
require "simple_oauth"

class Client
  Error = Class.new(RuntimeError)

  class Error < RuntimeError
    attr :response

    def initialize(res)
      @response = res
      super("#{res.class} (#{res.code}): #{res.body}")
    end
  end

  def initialize(key:, secret:, endpoint:)
    @key = key
    @secret = secret
    @endpoint = endpoint
    @http = Net::HTTP::Persistent.new
  end

  def request(method, path, body: {}, oauth: {})
    uri = URI.join(@endpoint, path)

    if method == "POST"
      req = Net::HTTP::Post.new(uri.path)
      req.set_form_data(body)
    else
      req = Net::HTTP::Get.new(uri.path)
    end

    oauth = oauth.merge(consumer_key: @key, consumer_secret: @secret)

    req["Authorization"] = SimpleOAuth::Header.new(method, uri.to_s, body, oauth).to_s

    res = @http.request(uri, req)

    if Integer(res.code) / 100 > 3
      raise Error.new(res)
    end

    res
  end
end
