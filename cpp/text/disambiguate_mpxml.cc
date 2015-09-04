/*
 * Example program to issue a disambiguate.mpxml request using libcurl
 * Uses multipart request suitable to enclose a large document
 * Uses multipart response suitable for delayed processing as the
 * part can easily be detached and stored for later usage.
 *
 * Environment variables IDILIA_ACCESS_KEY and IDILIA_PRIVATE_KEY must be set
 * to the keys obtained from https://www.idilia.com/developer/my-projects
 *
 * Requires the RPMs: mhash-devel curl-devel libxml2-devel
 *
 * Compile with:
 *   g++ -o disambiguate_mpxml -I /usr/include/libxml2 -lxml2 -lmhash -lcurl disambiguate_mpxml.cc
 *
 */

#include <libxml/parser.h>
#include <libxml/tree.h>
#include <libxml/xmlversion.h>
#include <libxml/xmlwriter.h>
#include <libxml/xpath.h>

#include <curl/curl.h>
#include <curl/easy.h>

#include <mhash.h>

#include <string>
#include <map>
#include <vector>
#include <stdexcept>
#include <iostream>
#include <sstream>

using namespace std;


// Simple class for parsing an HTTP multipart response given that not provided by libcurl
struct MultipartHttpResponse
{
  bool parse()
  {
    // Get the boundary. It starts at the 3rd character (after --) and ends with the \r\n
    if (body.length() < 2 || body[0] != '-' || body[1] != '-')
      return false;
    string partDelim(body, 0, body.find("\r\n"));

    // Split all the parts and their headers
    for (string::size_type partPos = body.find(partDelim) + partDelim.length(); body[partPos] != '-'; )
    {
      string::size_type hdrStPos = partPos + 2;
      string::size_type bodyPos = body.find("\r\n\r\n", hdrStPos);
      if (bodyPos == string::npos)
        return false;

      bodyPos += 4;
      string::size_type bodyEndPos = body.find(partDelim, bodyPos);
      if (bodyEndPos == string::npos)
        return false;

      partPos = bodyEndPos + partDelim.length();
      parts.push_back(Part());
      Part & part = parts.back();

      // Split the headers
      for (string::size_type hdrPos = hdrStPos, hdrNextPos; hdrPos < bodyPos && body[hdrPos] != '\r'; hdrPos = hdrNextPos + 2) {
        hdrNextPos = body.find("\r\n", hdrPos);
        string::size_type delimPos = body.find(": ", hdrPos);
        string key = body.substr(hdrPos, delimPos - hdrPos);
        delimPos += 2;
        string val = body.substr(delimPos, hdrNextPos - delimPos);
        part.headers[key] = val;
      }

      part.body.assign(body, bodyPos, bodyEndPos - bodyPos - 2);
    }
    return true;
  }

  struct Part {
    map<string, string> headers;
    string body;
  };

  vector<Part> parts; // the parts that can be read by the application
  string body;        // temporary buffer for accumulating the HTTP response
};


// A helper class to use with curl for reading the server's response into a MultipartHttpResponse
struct MultipartHttpResponseCurlReader
{
  MultipartHttpResponseCurlReader(MultipartHttpResponse * p) : pResp_(p) {}
  MultipartHttpResponse * pResp_;

  // Curl uses this function to provide the contents of the file downloaded
  static size_t readCallback( void *ptr, size_t size, size_t nmeb, void *stream)
  {
    MultipartHttpResponseCurlReader & reader = *((MultipartHttpResponseCurlReader *) stream);
    int readSz = size * nmeb;
    reader.pResp_->body.append((char *)(ptr), readSz);
    return readSz;
  }
};


// Helper function to assemble url-encoded parameters from a map
string convertToQueryParms(CURL * curl, const map<string, string> & parms) {
  string res;
  for (map<string, string>::const_iterator it = parms.begin(); it != parms.end(); ++it) {
    res += it->first;
    res += '=';
    char * encoded = curl_easy_escape(curl , it->second.c_str(), it->second.length());
    res += encoded;
    curl_free(encoded);
    res += '&';
  }
  res.erase(--res.end());
  return res;
}


// Encode a binary buffer to base64.
// We're going to do this using a function from libxml2 that should be
// readily available. If not, one can substitute with any other implementation.
string encodeBase64(const unsigned char * p, unsigned len)
{
  xmlBufferPtr buf = xmlBufferCreate();
  xmlTextWriterPtr writer = xmlNewTextWriterMemory(buf, 0);
  xmlTextWriterWriteBase64(writer, (const char *)p, 0, len);
  xmlTextWriterEndDocument(writer);
  xmlFreeTextWriter(writer);
  string encoded((const char *)buf->content);
  if (*encoded.rbegin() == '\n')
    encoded.erase(--encoded.end());
  xmlBufferFree(buf);
  return encoded;
}


// Add Idilia's authentication headers to the CURL request
curl_slist * addSignature(const char * hostname, string resource, const char * text, unsigned textLen, curl_slist * headers)
{
  static const char * accessKey = 0;
  static const char * privateKey = 0;
  if (!accessKey || !privateKey)
  {
    accessKey = getenv ("IDILIA_ACCESS_KEY");
    privateKey = getenv ("IDILIA_PRIVATE_KEY");
    if (!accessKey || !privateKey)
      throw runtime_error("Environment variables IDILIA_ACCESS_KEY and IDILIA_PRIVATE_KEY must be set.");
  }

  // Get the date in HTTP format
  char date[100];
  {
    string rfc2616 = "%a, %d %b %Y %H:%M:%S %Z";
    time_t t = time(NULL);
    strftime(date, sizeof(date), rfc2616.c_str(), gmtime(&t));
  }
  string dateHeader = string("Date: ") + date;
  headers = curl_slist_append(headers, dateHeader.c_str());

  string hostHeader = string("Host: ") + hostname;
  headers = curl_slist_append(headers, hostHeader.c_str());

  // Compute base64 of the MD5 of the text to send
  string md5;
  {
    MHASH td = mhash_init(MHASH_MD5);
    mhash(td, text, textLen);
    std::vector<unsigned char> bytes(mhash_get_block_size(MHASH_MD5));
    mhash_deinit(td, &*bytes.begin());
    md5 = encodeBase64(&bytes[0], bytes.size());
  }

  // Compute the authorization header
  string signature;
  {
    MHASH td = mhash_hmac_init(MHASH_SHA256, const_cast<char *>(privateKey), strlen(privateKey), mhash_get_hash_pblock(MHASH_SHA256));
    mhash(td, date, strlen(date));
    mhash(td, "-", 1);
    mhash(td, hostname, strlen(hostname));
    mhash(td, "-", 1);
    mhash(td, resource.c_str(), resource.length());
    mhash(td, "-", 1);
    mhash(td, md5.c_str(), md5.length());

    std::vector<unsigned char> bytes(mhash_get_block_size(MHASH_SHA256));
    mhash_hmac_deinit(td, &*bytes.begin());
    signature = encodeBase64(&bytes[0], bytes.size());
  }

  string authHeader = string("Authorization: IDILIA ") + accessKey + ":" + signature;
  headers = curl_slist_append(headers, authHeader.c_str());

  return headers;
}


int main(int argc, char **argv)
{
  // Set your environment variables to the keys obtained from https://www.idilia.com/developer/my-projects

  // Global initializations to do only once
  curl_global_init(CURL_GLOBAL_ALL);
  LIBXML_TEST_VERSION;

  // Set the locale to English to get RFC2616 HTTP dates with English day names.
  // Also set to utf8 because libxml will output utf8 strings.
  if (!setlocale(LC_ALL, "en_US.utf8"))
    throw runtime_error("Could not set the locale to english. Needed for authentication.");

  // The text that we will process
  string text = "JFK was shot in Dallas.";
  string textMime = "text/plain; charset=UTF-8";
  string resource = "/1/text/disambiguate.mpxml";
  string url = string("http://api.idilia.com") + resource;

  // Get a CURL handle for the request. We upload a multipart and get back a multipart.
  CURL * curl = curl_easy_init();
  if (!curl)
    throw std::runtime_error("Could not obtain CURL handle");

  // Parameters for the request
  map<string, string> parms;
  parms["requestId"] = "my-request";
  string encParms = convertToQueryParms(curl, parms);

  // Curl can assemble a multipart request
  struct curl_httppost *formpost=NULL;
  struct curl_httppost *lastptr=NULL;
  curl_formadd(&formpost, &lastptr,
      CURLFORM_PTRNAME, "parms",
      CURLFORM_PTRCONTENTS, encParms.c_str(), CURLFORM_CONTENTSLENGTH, encParms.length(),
      CURLFORM_CONTENTTYPE, "application/x-www-form-urlencoded; charset=UTF-8",
      CURLFORM_END);
  curl_formadd(&formpost, &lastptr,
      CURLFORM_PTRNAME, "doc",
      CURLFORM_PTRCONTENTS, text.c_str(), CURLFORM_CONTENTSLENGTH, text.length(),
      CURLFORM_CONTENTTYPE, textMime.c_str(),
      CURLFORM_END);
  curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
  curl_easy_setopt(curl, CURLOPT_HTTPPOST, formpost);
  // Turn on security both on peer and host
  curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 1L);
  curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 2L);

  // Setup to recover the downloaded content in an instance of MultipartHttpResponse
  MultipartHttpResponse response;
  MultipartHttpResponseCurlReader reader(&response);
  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, &MultipartHttpResponseCurlReader::readCallback);
  curl_easy_setopt(curl, CURLOPT_WRITEDATA, &reader);

  // setup headers for authentication
  struct curl_slist *headers=NULL;
  headers = curl_slist_append(headers, "Expect:"); // Don't wait for this
  headers = addSignature("api.idilia.com", resource, text.c_str(), text.length(), headers);
  curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);

   // Do it.
  CURLcode cc = curl_easy_perform(curl);
  if (cc != CURLE_OK)
  {
    stringstream ss; ss << curl_easy_strerror(cc);
    throw std::runtime_error(ss.str());
  }

  long httpCode = 0;
  curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &httpCode);
  if (httpCode != 200) // would be 202 if batch mode
  {
    stringstream ss; ss << httpCode << ' ' << response.body;
    throw std::runtime_error(ss.str());
  }

  // Cleanup
  curl_easy_cleanup(curl);
  curl_formfree(formpost);
  curl_slist_free_all(headers);

  // Get to the response
  if (!response.parse() || response.parts.size() != 2)
    throw std::runtime_error("Got unexpected response: " + response.body);


  // Parse the first part which is the application response to ensure that no errors
  // For this we can use the simple tree functions of libxml
  {
    xmlDocPtr doc = xmlReadMemory(response.parts[0].body.c_str(), response.parts[0].body.length(), NULL, NULL, 0);
    if (!doc)
      throw std::runtime_error("Could not recover content from " + response.parts[0].body);
    xmlNodePtr root = xmlDocGetRootElement(doc);
    bool foundError = false;
    for (xmlNodePtr child = root->xmlChildrenNode; child; child = child->next)
    {
      xmlChar *key = xmlNodeListGetString(doc, child->xmlChildrenNode, 1);
      if (key)
      {
        cout << "Got element " << child->name << " with value: " << key << endl;
        foundError = foundError || 0 == xmlStrcmp(child->name, (const xmlChar *) "errorMsg");
        xmlFree(key);
      }
      if (foundError)
        throw std::runtime_error("Got unexpected error");
    }

    xmlFreeDoc(doc);
  }


  // Parse the semdoc document to get all the found fine senses.
  // We could use the XmlTextReader to limit memory
  // usage but its easier to use Xpath on a Doc.
  {
    xmlDocPtr doc = xmlReadMemory(response.parts[1].body.c_str(), response.parts[1].body.length(), NULL, NULL, 0);
    if (!doc)
      throw std::runtime_error("Could not recover semdoc format");

    cout << "Got senses:" << endl;
    xmlXPathContextPtr context = xmlXPathNewContext(doc);
    xmlXPathObjectPtr result = xmlXPathEvalExpression((const xmlChar *) "//fs", context);
    for (int i = 0; i < result->nodesetval->nodeNr; i++)
    {
      xmlChar * sk = xmlGetProp(result->nodesetval->nodeTab[i], (const xmlChar *) "sk");
      cout << "  " << sk << endl;
      xmlFree(sk);
    }
    xmlXPathFreeObject(result);
    xmlXPathFreeContext(context);
    xmlFreeDoc(doc);
  }


  // Global cleanup done once
  xmlCleanupParser();
  curl_global_cleanup();
  return 0;
}
