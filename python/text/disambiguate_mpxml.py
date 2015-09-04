#
# Example program for issuing disambiguate.mpxml request
# Uses a multipart request suitable to enclose a large document
# Uses a multipart response suitable for delayed processing as the
# part can easily be detached and stored for later usage.
#

import urllib
import os
import httplib
import urlparse
import hashlib
import hmac, base64
import zlib
import re
import xml.etree.cElementTree as xml
from email.utils import formatdate
from datetime import datetime
from time import mktime

URL = "http://api.idilia.com/1/text/disambiguate.mpxml"
ACCESS_KEY = os.environ.get("IDILIA_ACCESS_KEY")
PRIVATE_KEY = os.environ.get("IDILIA_PRIVATE_KEY")
if (ACCESS_KEY == None or PRIVATE_KEY == None or len(ACCESS_KEY) == 0 or len(PRIVATE_KEY) == 0):
  raise Exception("You have to set environment variables IDILIA_ACCESS_KEY and IDILIA_PRIVATE_KEY")


#
# Simple class to format an HTTP multipart POST request given that httplib does not
# know how to do that
# Using this class avoids having to urlencode the possibly large document
class MultipartHttpPostRequest(object):
  def __init__(self, bdy = "--------YmM9XyV7I10ncTJJSzZD"):
    self.boundary = bdy
    self.parts = []
    self.contentType = 'multipart/mixed; boundary=%s' % self.boundary

  def addPart(self, headers, payload):
    h = "\r\n".join([": ".join(h) for h in headers.items()])
    self.parts.append("%s\r\n\r\n%s\r\n" % (h, payload))

  def encoded(self):
    delimiter = "--%s\r\n" % self.boundary
    parts = delimiter.join(self.parts)
    return "--%s\r\n%s--%s--" % (self.boundary, parts, self.boundary)


# Similar class for parsing an HTTP multipart response
#  member "parts" is an array of Hash with keys :body, and :headers (another hash)
class MultipartHttpResponse(object):
  def __init__(self, contentType, body):
    self.parts = []
    bdyV = re.search('boundary="?([\-\w]*)($|"|;)', contentType).group(1)
    tmpParts = body.split("--%s" % bdyV)
    for p in tmpParts[1:-1]:
      hb = p[2:-2].split("\r\n\r\n", 2)
      headers = dict([h.split(': ', 2)  for h in hb[0].split("\r\n")])
      self.parts.append({"headers" : headers, "body" : hb[1] })


# Setup the HTTP connection. It can be re-used for multiple 
# consecutive requests as we use HTTP 1.1
url = urlparse.urlparse(URL)
httpConn = httplib.HTTPConnection(url.hostname, url.port, timeout=4000)

text = "JFK was shot in Dallas."
    
# Compute the authorization
date = formatdate(timeval=mktime(datetime.utcnow().timetuple()), localtime=True, usegmt=True)
md5 = base64.b64encode(hashlib.md5(text).digest())
toSign = "%s-%s-%s-%s" % (date, url.hostname, url.path, md5)
signature = str(base64.b64encode(hmac.new(PRIVATE_KEY, toSign, hashlib.sha256).digest()))

# The request parameters. These don't include "text" and textMime
# Request the semdoc with gzip encoding
params = {
  'requestId' : 'mytest',
  'resultMime' : 'application/x-semdoc+xml+gz'
}


# Create the multipart request and populate it with the parms and the text
request = MultipartHttpPostRequest()
request.addPart({"Content-Type" : "application/x-www-form-urlencoded; charset=UTF-8"}, urllib.urlencode(params))
request.addPart({"Content-Type" : "text/plain; charset=UTF-8"}, text.encode("UTF-8"))

# Create the POST request and send it
headers = {
    'Accept-Encoding' : 'gzip',
    'Authorization' : "IDILIA %s:%s" % (ACCESS_KEY, signature),
    'Content-Type': request.contentType,
    'Date' : date,
    'Host' : url.hostname
}

httpConn.request("POST", url.path, request.encoded(), headers)

# Get the response and validate that no errors
httpResponse = httpConn.getresponse();
httpBody = httpResponse.read();
if httpResponse.getheader("Content-Encoding") == "gzip":
  httpBody = zlib.decompress(httpBody, 16+zlib.MAX_WBITS)

if httpResponse.status != httplib.OK:
  raise Exception(httpBody, httpResponse.status, httpResponse.reason)


# Parse the response. Should always be multipart
ct = httpResponse.getheader('Content-Type')
if not ct.startswith('multipart'):
  raise Exception("Received unexpected non-multipart")

# Parse the multipart response
response = MultipartHttpResponse(ct, httpBody)

# First part contains the XML object with status/errorMsg/requestId
disResp = xml.fromstring(response.parts[0]["body"])
if disResp.find('errorMsg') != None:
  raise Exception(disResp.find('errorMsg').text, disResp.find('status').text)
print "Got response for request: " + disResp.find('requestId').text

# Second part contains the compressed semdoc document
body = zlib.decompress(response.parts[1]["body"], 16+zlib.MAX_WBITS)
semdoc = xml.fromstring(body)
print "Found senses:"
for fs in semdoc.findall(".//fs"):
  print "  " + fs.attrib['sk']
  