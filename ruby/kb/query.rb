# encoding: UTF-8
#
# Example script to issue a query.json request
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

# The queries that we'll process. For an explanation of these queries,
# see the examples section in http://www.idilia.com/developer/language-graph/api/language-graph-query-specifications/
queries = [
  { "lemma" => "Montréal", "fsk" => [{ "fsk" => nil, "definition" => nil, "extRefs" => [], "neInfo" => nil }] },
  { "lemma" => "kiss", "caseVariants" => [{ "lemma" => nil, "fsk" => [] }] },
  { "lemma" => "chair", "fs" => [{ "fs" => nil, "lemma" => [], "definition" => nil, 
    "parents" => [{ "fs" => nil, "lemma" => [], "definition" => nil }], "categories" => [] }]
  }
]


# Open up a connection that we can re-use for several requests
uri = URI('http://api.idilia.com/1/kb/query.json')
Net::HTTP.start(uri.host, uri.port) do | http |

  # Convert the data structure to a JSON string that we can use
  # for computing the signature and transmitting
  qryS = JSON.dump(queries)
  
  # Compute the authorization
  date = Time.now.httpdate()
  md5 = Base64.encode64(Digest::MD5.digest(qryS)).chomp
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
      'query' => qryS,
      'requestId' => 'my-request'
    })
  request.set_content_type('application/x-www-form-urlencoded; charset=UTF-8')

  # Get the response and decode it
  httpResponse = http.request(request)
  body = httpResponse.body
  body = Zlib::Inflate.new(16+Zlib::MAX_WBITS).inflate(body) if httpResponse['Content-Encoding'] == 'gzip'

  # Parse the response and display it with pretty format
  case httpResponse
  when Net::HTTPOK
    resp = JSON.parse(body)
    puts "Server response:"
    puts JSON.pretty_generate(JSON.parse(body))
    puts

  else
    puts body
    raise "Some unexpected error occured when processing query [#{qryS}]"
  end
end
