# encoding: UTF-8
#
# Example script to issue a disambiguate.xml request
# Uses in-line source text and response. Suitable for short documents
# processed immediately on response.
#
require 'rubygems'
require 'uri'
require 'net/http'
require 'digest/md5'
require 'openssl'
require 'base64'
require 'time'
require 'zlib'
require 'rexml/document'

# Set your environment variables to the keys obtained from https://www.idilia.com/developer/my-projects
accessKey = ENV['IDILIA_ACCESS_KEY'] || ""
privateKey = ENV['IDILIA_PRIVATE_KEY'] || ""
raise "You have to set environment variables IDILIA_ACCESS_KEY and IDILIA_PRIVATE_KEY" if accessKey.empty? or privateKey.empty?

# The text that we'll process
text="JFK was shot in Dallas."
textMime="text/plain; charset=UTF-8"

# Open up a connection that we can re-use for several requests
uri = URI('http://api.idilia.com/1/text/disambiguate.xml')
Net::HTTP.start(uri.host, uri.port) do | http |

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
    puts "Found senses: "
    semdoc = REXML::Document.new(body)
    semdoc.elements.each("//fs") do | fs |
      puts "  #{fs.attributes["sk"]} with confidence #{fs.attributes["pc"]}" 
    end

  else
    puts body
    raise "Some unexpected error occured"
  end
end
