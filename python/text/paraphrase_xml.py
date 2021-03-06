#
# Example program for issuing paraphrase.xml request
# processed immediately on response.
#

import urllib
import os
import httplib
import urlparse
import hashlib
import hmac, base64
import zlib
import xml.etree.cElementTree as xml
from email.utils import formatdate
from datetime import datetime
from time import mktime

URL = "http://api.idilia.com/1/text/paraphrase.xml"
ACCESS_KEY = os.environ.get("IDILIA_ACCESS_KEY")
PRIVATE_KEY = os.environ.get("IDILIA_PRIVATE_KEY")
if (ACCESS_KEY == None or PRIVATE_KEY == None or len(ACCESS_KEY) == 0 or len(PRIVATE_KEY) == 0):
  raise Exception("You have to set environment variables IDILIA_ACCESS_KEY and IDILIA_PRIVATE_KEY")


# Setup the HTTP connection. It can be re-used for multiple 
# consecutive requests as we use HTTP 1.1
url = urlparse.urlparse(URL)
httpConn = httplib.HTTPConnection(url.hostname, url.port, timeout=4000)

# Create the request params.
texts=["porch lights", "car engine problems diagnosing", "nikon digital camera"]

for text in texts:
  # Compute the authorization
  date = formatdate(timeval=mktime(datetime.utcnow().timetuple()), localtime=True, usegmt=True)
  md5 = base64.b64encode(hashlib.md5(text).digest())
  toSign = "%s-%s-%s-%s" % (date, url.hostname, url.path, md5)
  signature = str(base64.b64encode(hmac.new(PRIVATE_KEY, toSign, hashlib.sha256).digest()))
  
  # The request parameters
  params = {
    'requestId' : 'mytest',
    'text' : text,
    'maxCount' : 10,
    'minWeight' : 0.5,
    'paraphrasingRecipe' : 'productSearch',
    'textMime' : "text/query; charset=us-ascii"
  }
  
  # The HTTP headers that we use: Mostly for validation
  headers = {
      'Accept-Encoding': 'gzip',
      'Authorization' : "IDILIA %s:%s" % (ACCESS_KEY, signature),
      'Content-Type': "application/x-www-form-urlencoded; charset=UTF-8",
      'Date' : date,
      'Host' : url.hostname
  }
  
  # Send the POST request and send it
  httpConn.request("POST", url.path, urllib.urlencode(params), headers)
  
  # Get the response and decode it
  httpResponse = httpConn.getresponse();
  httpBody = httpResponse.read();
  if httpResponse.getheader("Content-Encoding") == "gzip":
    httpBody = zlib.decompress(httpBody, 16+zlib.MAX_WBITS)
  
  # First validation in case something went wrong in the transport layer
  if httpResponse.status != httplib.OK:
      raise Exception(httpBody, httpResponse.status, httpResponse.reason)
  
  # Application layer validation
  resp = xml.fromstring(httpBody)
  if resp.find('errorMsg') != None:
      raise Exception(resp.find('errorMsg').text, resp.find('status').text)
  
  # Display the senses found.
  ccfmp = resp.find('queryConf/confCorrectFineMostProbable').text
  print "Paraphrases received for query: [%s] (overall conf: %s)" % (text, ccfmp)
  for p in resp.findall(".//paraphrase"):
    print "  [%s] with weight %s" % (p.find("surface").text, p.find("weight").text)
  print
