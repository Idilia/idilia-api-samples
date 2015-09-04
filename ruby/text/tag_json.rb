# encoding: UTF-8
#
# Example script to issue a tag.json request
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

# The text that we will tag
text="Since Kanye West got to do most of the talking during Taylor Swift's "\
     "aborted acceptance speech for Best Female Video, the country darling "\
     "took time at the end of the night to talk about the MTV Video Music Awards. "\
     "Her first reaction? \"I was really excited, because I had just won the award. "\
     "And then I was really excited because Kanye West was onstage,\" she said. "\
     "\"And then I wasn't so excited anymore after that.\" Rolling Stone has "\
     "learned that backstage, when Swift's mother approached West, he gave a "\
     "half-hearted apology in which he added he still thought Beyonce had a better video."
     
textMime="text/plain; charset=UTF-8"

# Open up a connection that we could re-use for several requests
uri = URI('http://api.idilia.com/1/text/tag.json')
Net::HTTP.start(uri.host, uri.port) do | http |

  # Create the HTTP request with the headers and parameters
  request = Net::HTTP::Post.new(uri.path, {
    'Accept-Encoding' => 'gzip',
    })
  request.set_form_data({
      'key' => accessKey + privateKey,
      'text' => text,
      'textMime' => textMime,
      'tag.repeatPolicy' => :tagRepeats,
      'tag.markup' => 'infocard,schemaOrg,title'
    })
  request.set_content_type('application/x-www-form-urlencoded; charset=UTF-8')

  # Get the response and decode it
  http.read_timeout = 3600 + 60; # slightly exceeds default value for parameter "timeout"
  httpResponse = http.request(request)
  body = httpResponse.body
  body = Zlib::Inflate.new(16+Zlib::MAX_WBITS).inflate(body) if httpResponse['Content-Encoding'] == 'gzip'
  resp = JSON.parse(body)

  # Parse the response
  case httpResponse
  when Net::HTTPOK
    puts "Got tagged text: #{resp["text"]}"
  else
    puts body
    raise "An unexpected error occurred when processing."
  end
end
