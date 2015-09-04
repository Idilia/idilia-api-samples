# encoding: UTF-8
#
# Example script to issue a disambiguate.mpxml request with multiple documents
# Uses a multipart request with a part per document
# Uses a multipart response with a part per result document
#
require 'rubygems'
require 'uri'
require 'net/http'
require 'digest/md5'
require 'openssl'
require 'base64'
require 'time'
require 'rexml/document'
require 'cgi'
require 'zlib'

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

# The texts that we'll process
texts=[
  "JFK was shot in Dallas.", 
  "Nelson Mandela spent several years in prison.", 
  "Marilyn Monroe wore Chanel No. 5 at night."
]
textMime="text/plain; charset=UTF-8"

# Make a request, specifying that we'll take an XML object
# as a response. We'll use a POST but could also use a GET
uri = URI('http://api.idilia.com/1/text/disambiguate.mpxml')
Net::HTTP.start(uri.host, uri.port) do | http |

  params = {
    'requestId' => 'mytest',
    'resultMime' => 'application/x-semdoc+xml+gz'
  }
  
  disReq = MultipartHttpPostRequest.new
  disReq.addPart({"Content-Type" => "application/x-www-form-urlencoded; charset=UTF-8"}, params.map{ |k,v| "#{k}=#{CGI.escape(v.to_s)}" }.join('&'))
  texts.each { |t| disReq.addPart({"Content-Type" => textMime}, t) }
  
  date = Time.now.httpdate()
    
  md5 = texts.inject(Digest::MD5.new) { |d, t| d << t }
  md5 = Base64.encode64(md5.digest).chomp
  toSign=date + '-' + uri.host + '-' + uri.path + '-' + md5
  signature=Base64.encode64(OpenSSL::HMAC.digest('sha256', privateKey, toSign)).chomp
  authorization = "IDILIA " + accessKey + ":" + signature

  request = Net::HTTP::Post.new(uri.path, {
    'Accept-Encoding' => 'gzip',
    'Authorization' => authorization,
    'Content-Type' => disReq.contentType,
    'Date' => date,
    'Host' => uri.host
    })
    
  request.body = disReq.encoded
  
  http.read_timeout = 3600 + 60; # slightly exceeds default value for parameter "timeout"
  httpResponse = http.request(request)
  body = httpResponse.body
  body = Zlib::Inflate.new(16+Zlib::MAX_WBITS).inflate(body) if httpResponse['Content-Encoding'] == 'gzip'

  case httpResponse
  when Net::HTTPOK
    # Parse the multipart response
    response = MultipartHttpResponse.new(httpResponse['Content-Type'], body)
    disResp = REXML::Document.new(response.parts[0][:body])
    puts "Got response for request: " + disResp.elements["//requestId"][0].to_s
    
    (1...response.parts.length).each do | partIdx |
      puts "For text: "  + texts[partIdx-1]
      puts "Found senses: "
      body = Zlib::Inflate.new(16+Zlib::MAX_WBITS).inflate(response.parts[partIdx][:body])
      semdoc = REXML::Document.new(body)
      semdoc.elements.each("//fs") do | fs |
        puts "  " + fs.attributes["sk"]
      end
    end
    
  else
    puts body
    raise "Some unexpected error occurred"
  end
end

