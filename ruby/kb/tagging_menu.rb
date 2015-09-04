# encoding: UTF-8
#
# Example script to issue a kb/tagging_menu.json request
# Uses the text/disambiguate.mpxml to obtain the sense analysis
# results for the text to sense tag and then the kb/tagging_menu.json
# API to obtain the tagging menu.
#
# This is an example of the "server" side code. The menu obtained
# would be relayed to matching javascript client code and animated
# using the jquery_tagging_menu.js plugin.
#

require 'rubygems'
require 'uri'
require 'net/http'
require 'digest/md5'
require 'openssl'
require 'base64'
require 'time'
require 'cgi'
require 'zlib'
require 'json'

#
# Simple class to format an HTTP multipart POST request given that net/http does not
# know how to do that and there are subtle differences between a mail and http multipart
# Using this class avoids having to urlencode the possibly large document
class MultipartHttpPostRequest
  attr_reader :contentType
  def initialize(bdy = "--------YmM9XyV7I10ncTJJSzZD")
    @boundary = bdy
    @parts = []
    @contentType = "multipart/mixed; boundary=#{@boundary}"
  end

  def addPart(headers, payload)
    @parts << headers.to_a.inject('') { |t, hv|  t << hv.join(': ') << "\r\n" } + "\r\n#{payload}\r\n"
  end

  def encoded
    delimiter = "--#{@boundary}\r\n"
    return "--#{@boundary}\r\n#{@parts.join(delimiter)}--#{@boundary}--"
  end
end

# Similar class for parsing an HTTP multipart response
class MultipartHttpResponse
  attr_reader :parts # An array of Hash with keys :body, and :headers (another hash)
  def initialize(contentType, body)
    @parts = []
    bdyV = contentType.match('boundary="?([\-\w]*)($|"|;)')[1]
    tmpParts = body.split("--#{bdyV}")
    tmpParts[1...-1].each do | p |
      header, body = p[2...-2].split("\r\n\r\n", 2)
      headers = Hash[*header.split("\r\n").collect { | h | h.split(': ', 2) }.flatten]
      @parts << {:headers => headers, :body => body }
    end
  end
end

# Set your environment variables to the keys obtained from https://www.idilia.com/developer/my-projects
accessKey = ENV['IDILIA_ACCESS_KEY'] || ""
privateKey = ENV['IDILIA_PRIVATE_KEY'] || ""
raise "You have to set environment variables IDILIA_ACCESS_KEY and IDILIA_PRIVATE_KEY" if accessKey.empty? or privateKey.empty?

# The text that we'll process - sample search expression
text="tide cheer gain"

# Preprocessing to run on search expression to restrict the
# tagging menus on appropriate content
text = text.
    # split off parentheses
    gsub(/([()])/, ' \1 ').
    # strip white space at beginning and end
    strip().
    # normalize spacing, multiple spaces into one
    gsub(/\s+/, ' ').
    # replace spaces preceding even number of quotes with underlines
    gsub(/\s(?=[^"]*"(?:[^"]*"[^"]*")*[^"]*$)/, '_').
    # wrap space delimited words with paragraphs
    gsub(/(?<=\s|^)([^ ]*?)(?=\s|$)/, '<p>\1</p>').
    # identify zones that we don't want to analyze
    gsub(/<p>([-].*?|OR)<\/p>/, '<p><span data-idl-fsk="ina">\1</span></p>').
    # replace back the underscores with spaces
    gsub('_', ' ') 

textMime="text/query-html;charset=utf8";

# URL for sense analysis specifies that we'll take a multipart response
# with the result document in a seperate part than the operation status
disUri = URI('http://api.idilia.com/1/text/disambiguate.mpjson')
tmUri = URI('http://api.idilia.com/1/kb/tagging_menu.json')

Net::HTTP.start(disUri.host, disUri.port) do | http |

  # First obtain sense analysis results
  
  # Compute the authorization
  date = Time.now.httpdate()
  md5 = Base64.encode64(Digest::MD5.digest(text)).chomp
  toSign=date + '-' + disUri.host + '-' + disUri.path + '-' + md5
  signature=Base64.encode64(OpenSSL::HMAC.digest('sha256', privateKey, toSign)).chomp
  authorization = "IDILIA " + accessKey + ":" + signature

  # Create the HTTP request with the headers and parameters
  # Request a resultMime of type 'application/x-tf+xml+gz because
  # that's is the expected input to the tagging_menu API.
  request = Net::HTTP::Post.new(disUri.path, {
    'Authorization' => authorization,
    'Date' => date,
    'Host' => disUri.host
    })
  request.set_form_data({
      'text' => text,
      'textMime' => textMime,
      'resultMime' => 'application/x-tf+xml+gz'
    })
  request.set_content_type('application/x-www-form-urlencoded; charset=UTF-8')

  # Get the response and decode it
  http.read_timeout = 3600 + 60; # slightly exceeds default value for parameter "timeout"
  httpResponse = http.request(request)
  body = httpResponse.body

  response = MultipartHttpResponse.new(httpResponse['Content-Type'], body)
  saRes = response.parts[1];
    
  #
  # Obtain the tagging menu
  # Create the multipart request with the data part the result part of
  # text/disambiguate.  
  
  # Compute the authorization using the data previously returned
  date = Time.now.httpdate()
  md5 = Base64.encode64(Digest::MD5.digest(saRes[:body])).chomp
  toSign=date + '-' + tmUri.host + '-' + tmUri.path + '-' + md5
  signature=Base64.encode64(OpenSSL::HMAC.digest('sha256', privateKey, toSign)).chomp
  authorization = "IDILIA " + accessKey + ":" + signature
  
  params = {
    'filters' => 'noDynamic'
  }
  menuReq = MultipartHttpPostRequest.new
  menuReq.addPart({"Content-Type" => "application/x-www-form-urlencoded; charset=UTF-8"}, params.map{ |k,v| "#{k}=#{CGI.escape(v.to_s)}" }.join('&'))
  menuReq.addPart(saRes[:headers], saRes[:body])

  request = Net::HTTP::Post.new(tmUri.path, {
    'Accept-Encoding' => 'gzip',
    'Authorization' => authorization,
    'Content-Type' => menuReq.contentType,
    'Date' => date,
    'Host' => tmUri.host
  })
  
  request.body = menuReq.encoded
  httpResponse = http.request(request)
  body = httpResponse.body
  body = Zlib::Inflate.new(16+Zlib::MAX_WBITS).inflate(body) if httpResponse['Content-Encoding'] == 'gzip'
    
  case httpResponse
  when Net::HTTPOK
    resp = JSON.parse(body)
    puts "Got words HTML as resp.text:" + resp["text"]
    puts "Got menu HTML as resp.menu:" + resp["menu"]
  
  else
    puts body
    raise "Some unexpected error occured"
  end
end
