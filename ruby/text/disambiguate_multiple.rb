# encoding: UTF-8
#
# Example script to issue a disambiguate.xml requests to process a file that contains several line
# where each line is a search query. The result for each line is stored in a file
# with the pattern "query_<n>.semdoc.xml" where <n> is the file line number.
# Several documents are generated at once using multiple threads.
# Uses in-line source text and response.
# Script can be re-ran multiple times if necessary.
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
require 'optparse'

# Set your environment variables to the keys obtained from https://www.idilia.com/developer/my-projects
ACCESS_KEY = ENV['IDILIA_ACCESS_KEY'] || ""
PRIVATE_KEY = ENV['IDILIA_PRIVATE_KEY'] || ""
raise "You have to set environment variables IDILIA_ACCESS_KEY and IDILIA_PRIVATE_KEY" if ACCESS_KEY.empty? or PRIVATE_KEY.empty?

OPTIONS = {}
OPTIONS[:iFile]="";        # Input file with all the queries
OPTIONS[:outDir]=""        # Output directory where output for each query is stored
OPTIONS[:maxSimReq] = 100; # Number of simultaneous requests. Limited by project profile associated with keys.

opts = OptionParser.new do | opts |
  opts.banner = "Usage: disambiguate_queries.rb [options]"
  
  opts.separator ""
  opts.separator "Specific options:"
  
  # Mandatory request
  opts.on("--input-file ARG", "File with the queries", String) { | req | OPTIONS[:iFile] = req }
  opts.on("--output-dir ARG", "Output directory") { | req | OPTIONS[:outDir] = req }
  
  opts.on( '-h', '--help', 'Display this screen' ) do
    puts opts
    exit
  end
  
  opts.parse!(ARGV)
end

raise "You must provide an input file using --input-file" if OPTIONS[:iFile].empty?
raise "You must provide an output directory using --output-dir" if OPTIONS[:outDir].empty?

TEXT_MIME="text/query; charset=UTF-8"
WSD_URI = URI('http://api.idilia.com/1/text/disambiguate.xml');
HOSTNAME = Socket.gethostname


# Helper function to obtain the WSD results for the given query
def disambiguateQuery(uri, http, oFile, qry, reqId)

  # Check if the document already exists or we already determined that it can't be computed
  return '200' if File.exists?(oFile)
  return '500' if File.exists?(oFile+".400") or File.exists?(oFile+".500")
  
  date = Time.now.httpdate()
  md5 = Base64.encode64(Digest::MD5.digest(qry)).chomp
  toSign=date + '-' + uri.host + '-' + uri.path + '-' + md5
  signature=Base64.encode64(OpenSSL::HMAC.digest('sha256', PRIVATE_KEY, toSign)).chomp
  authorization = "IDILIA " + ACCESS_KEY + ":" + signature

  request = Net::HTTP::Post.new(uri.path, {
    'Accept-Encoding' => 'gzip',
    'Authorization' => authorization,
    'Date' => date,
    'Host' => uri.host
    })
  request.set_form_data({
      'text' => qry,
      'textMime' => TEXT_MIME,
      'requestId' => reqId
    })
  request.set_content_type('application/x-www-form-urlencoded; charset=UTF-8')
    
  httpResponse = http.request(request);
  body = httpResponse.body
  body = Zlib::Inflate.new(16+Zlib::MAX_WBITS).inflate(body) if httpResponse['Content-Encoding'] == 'gzip'
  
  if httpResponse.code != '200'
    print "Got error code during wsd for reqId: " << reqId << " at " << Time.now.httpdate() << " response: " << httpResponse.code << "\n" << httpResponse.body << "\n"
    if httpResponse.code == '400'
      # Something wrong with this request. Create a file with error message.
      # so that we don't reattempt
      File.open(resultFn+".400", "w+").write(body)
      return httpResponse.code;
    elsif httpResponse.code[-3] == '5'
      # Server could not process. Save error message.
      File.open(resultFn+".500", "w+").write(body)
      return httpResponse.code;
    end
    return httpResponse.code
  end
  
  
  # Write the file
  handle = File.open(oFile+"~", "w+");
  handle.syswrite(body);
  File.rename(oFile+"~", oFile);
  return httpResponse.code;
end


#
# Start of mainline

# Ensure that output directory exists
Dir.mkdir(OPTIONS[:outDir]) unless File.directory?(OPTIONS[:outDir])

# Start to disambiguate all the lines in the given file using multiple threads
queries = File.open(OPTIONS[:iFile]).readlines
threads = []
(0...OPTIONS[:maxSimReq]).each do | thr |
  threads << Thread.new("wsd #{thr}") do | name |
    reqNum = 0;
    httpConn = nil;
    (0...queries.length).each do | qryIdx |
      if qryIdx.modulo(OPTIONS[:maxSimReq]) == thr
        reqNum += 1;
        qry = queries[qryIdx].chomp
        continue if qry.empty?
        requestId = "r-#{thr}-#{reqNum}";
        (0...2).each do | attempt |
          httpConn = httpConn || Net::HTTP.new(WSD_URI.host, WSD_URI.port);
          httpConn.read_timeout = 5000000
          begin
            oFile = File.join(OPTIONS[:outDir], "query_#{qryIdx}.semdoc.xml")              
            disambiguateQuery(WSD_URI, httpConn, oFile, qry, requestId)
            break
          rescue
            httpConn = nil;
          end
          sleep(1)
        end
      end
    end
  end
end
threads.each { |t| t.join }
