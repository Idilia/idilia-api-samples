# encoding: UTF-8
#
# This is a ruby script disambiguate multiple documents at the same time.
# The document are one liners from a supplied file
# Environment must contain IDILIA_ACCESS_KEY or IDILIA_PRIVATE_KEY unless specified.
#
# Example command line:
#  ruby disambiguate_multiple_mpxml.rb -i texts.txt -o ./outputdir


require 'uri'
require 'net/http'
require 'optparse'
require 'cgi'
require 'open-uri'
require 'digest/md5'
require 'openssl'
require 'base64'
require 'socket'
require 'time'
require 'zlib'
require 'fileutils'
require 'thread'

#
# The options provided on the command line
#
$options = {}
$options[:iFile]=""; # Input file with the one liners
$options[:outDir]=""        # Output directory where output for each query is stored
$options[:numThreads] = 5;
  
opts = OptionParser.new do | opts |
  opts.banner = "Usage: disambiguate_multiple.rb [options]"
  
  opts.separator ""
  opts.separator "Specific options:"
  
  # Mandatory request
  opts.on("-tARG", "--num-threads=ARG", "Number of simultaneous WSD requests", Integer) { | req | $options[:numThreads] = req }
  opts.on("--input-file=ARG", "File with the one liners", String) { | req | $options[:iFile] = req }
  opts.on("--output-dir=ARG", "Output directory") { | req | $options[:outDir] = req }
  opts.on("--access-key=ARG", "access key for Idilia") { | req | $options[:accessKey] = req }
  opts.on("--private-key=ARG", "private key for Idilia") { | req | $options[:privateKey] = req }
  
  opts.on( '-h', '--help', 'Display this screen' ) do
    puts opts
    exit
  end
  
  opts.parse!(ARGV)
end

WSD_URI = URI('http://api.idilia.com/1/text/disambiguate.mpxml');
ACCESS_KEY = $options[:accessKey] || ENV['IDILIA_ACCESS_KEY'] || ""
PRIVATE_KEY = $options[:privateKey] || ENV['IDILIA_PRIVATE_KEY'] || ""
raise "You have to set environment variables IDILIA_ACCESS_KEY and IDILIA_PRIVATE_KEY" if ACCESS_KEY.empty? or PRIVATE_KEY.empty?


# Class for parsing an HTTP multipart response
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


# Obtain the WSD results for the given document
def disambiguateDocument(file, text, reqId)

  # Ensure target directory exists
  resultDir = file.match('(.*)/.*.semdoc.xml')[1]
  FileUtils.mkpath(resultDir) unless File.directory?(resultDir)

  Net::HTTP.start(WSD_URI.host, WSD_URI.port) do | http |
    # Create the HTTP request with the headers and parameters
    date = Time.now.httpdate()
    md5 = Base64.encode64(Digest::MD5.digest(text)).chomp
    toSign=date + '-' + WSD_URI.host + '-' + WSD_URI.path + '-' + md5
    signature=Base64.encode64(OpenSSL::HMAC.digest('sha256', PRIVATE_KEY, toSign)).chomp
    authorization = "IDILIA " + ACCESS_KEY + ":" + signature
  
    request = Net::HTTP::Post.new(WSD_URI.path, {
      'Accept-Encoding' => 'gzip',
      'Authorization' => authorization,
      'Date' => date,
      'Host' => WSD_URI.host
      })
      
    request.set_form_data({
        'text' => text,
        'textMime' => 'text/plain; charset=utf8',
        'maxTokens' => -1,
        'requestId' => reqId
      })
    request.set_content_type('application/x-www-form-urlencoded; charset=UTF-8')
      
    print date << " Requesting WSD #{file} as #{reqId}\n"
    
    http.read_timeout = 4000
    httpResponse = http.request(request)
    body = httpResponse.body
    body = Zlib::Inflate.new(16+Zlib::MAX_WBITS).inflate(body) if httpResponse['Content-Encoding'] == 'gzip'

    if httpResponse.code != '200'
      print "Got error code during wsd for reqId: " << reqId << " at " << Time.now.httpdate() << " response: " << httpResponse.code << "\n" << httpResponse.body << "\n"
      return httpResponse.code
    else
      response = MultipartHttpResponse.new(httpResponse['Content-Type'], body)
      semdoc = response.parts[1][:body]
        
      # Write the file
      File.open(file, "w").write(semdoc);
      return httpResponse.code;
    end
  end
end


#
# Start of mainline
#

# Open the file with the one lines that we need to process
iFile = File.open($options[:iFile], 'r')

# Disambiguate all the documents, one per line
sema = Mutex.new
threads = []
docIdx = 0
(0...$options[:numThreads]).each { | thr |
  threads << Thread.new("wsd #{thr}") { | name |
    loop {
      begin
        # Read a line from the input file
        text = nil
        aDocIdx = nil;
        sema.synchronize {
          docIdx += 1
          aDocIdx = docIdx
          text = iFile.readline if !iFile.eof
        }
        break if text.nil?
        
        text.strip!
        next if text.empty?
        
        hash = ("000" + aDocIdx.to_s)[-4, 4]
        requestId = "r-#{aDocIdx}";
        oFile = File.join($options[:outDir], hash[0, 2],  hash[2,2], requestId + ".semdoc.xml")
        rc = disambiguateDocument(oFile, text, requestId)
      rescue Exception => e
        puts "Caught in thread #{thr}: #{e.message}"
        puts e.backtrace.inspect
      end
    }
  }
}
threads.each { |t| t.join }

