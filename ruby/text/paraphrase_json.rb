# encoding: UTF-8
#
# Example script to issue a paraphrase.json request
#
require 'rubygems'
require 'uri'
require 'net/http'
require 'digest/md5'
require 'openssl'
require 'base64'
require 'time'
require 'zlib'
require 'json'

# Set your environment variables to the keys obtained from https://www.idilia.com/developer/my-projects
accessKey = ENV['IDILIA_ACCESS_KEY'] || ""
privateKey = ENV['IDILIA_PRIVATE_KEY'] || ""
raise "You have to set environment variables IDILIA_ACCESS_KEY and IDILIA_PRIVATE_KEY" if accessKey.empty? or privateKey.empty?

# The queries that we'll process
texts=["porch lights", "car engine problems diagnosing", "nikon digital camera"]
textMime="text/query; charset=UTF-8"

# Open up a connection that we can re-use for several requests
uri = URI('http://api.idilia.com/1/text/paraphrase.json')
Net::HTTP.start(uri.host, uri.port) do | http |

  texts.each do | text |
    
    # Compute the authorization
    date = Time.now.httpdate()
    md5 = Base64.encode64(Digest::MD5.digest(text)).chomp
    toSign=date + '-' + uri.host + '-' + uri.path + '-' + md5
    signature=Base64.encode64(OpenSSL::HMAC.digest('sha256', privateKey, toSign)).chomp
    authorization = "IDILIA " + accessKey + ":" + signature
  
    # Create the HTTP request with the headers and parameters
    request = Net::HTTP::Post.new(uri.path, {
      'Accept-Encoding' => 'gzip',
      'Authorization' => authorization,
      'Date' => date,
      'Host' => uri.host
      })
    request.set_form_data({
        'text' => text,
        'textMime' => textMime,
        'maxCount' => 10,
        'minWeight' => 0.5,
        'paraphrasingRecipe' => 'productSearch',
        'requestId' => 'my-request'
      })
    request.set_content_type('application/x-www-form-urlencoded; charset=UTF-8')
  
    # Get the response and decode it
    http.read_timeout = 3600 + 60; # slightly exceeds default value for parameter "timeout"
    httpResponse = http.request(request)
    body = httpResponse.body
    body = Zlib::Inflate.new(16+Zlib::MAX_WBITS).inflate(body) if httpResponse['Content-Encoding'] == 'gzip'
  
    # Parse the response
    case httpResponse
    when Net::HTTPOK
      resp = JSON.parse(body)
      ccfmp = resp["queryConf"]["confCorrectFineMostProbable"]
      puts "Paraphrases received for query: [#{text}] (overall conf: #{ccfmp})"
      resp["paraphrases"].each do | p |
        puts "  [#{p["surface"]}] with weight #{p["weight"]}"
      end
      puts
  
    else
      puts body
      raise "Some unexpected error occured when processing query [#{text}]"
    end
  end
end
