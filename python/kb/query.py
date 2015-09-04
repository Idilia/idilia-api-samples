# -*- coding: UTF-8 -*-
#
# Example program for issuing paraphrase.json request
# processed immediately on response.
#

import urllib
import os
import httplib
import urlparse
import hashlib
import hmac, base64
import zlib
import json
from email.utils import formatdate
from datetime import datetime
from time import mktime

URL = "http://api.idilia.com/1/kb/query.json"
ACCESS_KEY = os.environ.get("IDILIA_ACCESS_KEY")
PRIVATE_KEY = os.environ.get("IDILIA_PRIVATE_KEY")
if (ACCESS_KEY == None or PRIVATE_KEY == None or len(ACCESS_KEY) == 0 or len(PRIVATE_KEY) == 0):
  raise Exception("You have to set environment variables IDILIA_ACCESS_KEY and IDILIA_PRIVATE_KEY")


# Setup the HTTP connection. It can be re-used for multiple 
# consecutive requests as we use HTTP 1.1
url = urlparse.urlparse(URL)
httpConn = httplib.HTTPConnection(url.hostname, url.port)

# The queries that we'll process. For an explanation of these queries,
# see the examples section in http://www.idilia.com/developer/language-graph/api/language-graph-query-specifications/
queries = [
  { "lemma" : "Montreal", "fsk" : [{ "fsk" : None, "definition" : None, "extRefs" : [], "neInfo" : None }] },
  { "lemma" : "kiss", "caseVariants" : [{ "lemma" : None, "fsk" : [] }] },
  { "lemma" : "chair", "fs" : [{ "fs" : None, "lemma" : [], "definition" : None, 
    "parents" : [{ "fs" : None, "lemma" : [], "definition" : None }], "categories" : [] }]
  }
]

# Convert the data structure to a JSON string that we can use
# for computing the signature and transmitting
qryS = json.dumps(queries, separators=(',',':'))
  
# Compute the authorization
date = formatdate(timeval=mktime(datetime.utcnow().timetuple()), localtime=True, usegmt=True)
md5 = base64.b64encode(hashlib.md5(qryS).digest())
toSign = "%s-%s-%s-%s" % (date, url.hostname, url.path, md5)
signature = str(base64.b64encode(hmac.new(PRIVATE_KEY, toSign, hashlib.sha256).digest()))

# The request parameters
params = {
  'requestId' : 'mytest',
  'query' : qryS
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
resp = json.loads(httpBody)
if resp.has_key('errorMsg'):
    raise Exception(resp['errorMsg'], resp['status'])

# Display the response in pretty format
print json.dumps(resp, ensure_ascii=False, indent=2)
