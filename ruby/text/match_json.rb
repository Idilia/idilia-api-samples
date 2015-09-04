# encoding: UTF-8
#
# Example script to issue a match.json request
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

# The Tweets that we'll process
texts=[
  "RT @blecklerr: just saw a southern tide decal on a nissan with dark tint and the biggest shiniest rims. #theyreconfused #WhatsGoingOnHere",
  "In honor of the Crimson Tide, here's the song of the day. Welcome to Miami, vien bonito amiami !! See you at... http://t.co/vdkan4mN"
]
textMime="text/tweet; charset=UTF-8"

# Open up a connection that we can re-use for several requests
uri = URI('http://api.idilia.com/1/text/match.json')
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
        'filter' => '{"fsk":"tide/N1"}',
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
      puts text
      if resp.has_key?("matches")
        resp["matches"].each do | m |
          if m.has_key?("foundSk")
            puts "  Found identify or equivalent sensekey #{m["foundSk"]} at offset #{m["position"][0]} with confidence #{m["conf"]} and for reason #{m["reasons"][0]}"
          else
            puts '  Word match but wrong sense'
          end
        end
      else
        puts "  No word match"
      end
    else
      puts body
      raise "  Some unexpected error occured when processing query [#{text}]"
    end
    puts
  end
end
