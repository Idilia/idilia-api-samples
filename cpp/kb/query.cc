/*
 * Example program to issue a query.json request using libcurl
 *
 * Environment variables IDILIA_ACCESS_KEY and IDILIA_PRIVATE_KEY must be set
 * to the keys obtained from https://www.idilia.com/developer/my-projects
 *
 * Requires the RPMs: mhash-devel curl-devel libxml2-devel
 *
 * Compile with:
 *   g++ -o query -I /usr/include/libxml2 -lxml2 -lmhash -lcurl query.cc
 *
 */

#include <libxml/xmlwriter.h>
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


// Curl helper function for storing the response downloaded from the server
size_t curlCallback( void *ptr, size_t size, size_t nmeb, void *stream)
{
  string & buffer = *((string *) stream);
  int readSz = size * nmeb;
  buffer.append((const char *)ptr, readSz);
  return readSz;
}


int main(int argc, char **argv)
{
  // Set your environment variables to the keys obtained from https://www.idilia.com/developer/my-projects

  // Global initializations to do only once
  curl_global_init(CURL_GLOBAL_ALL);

  // Set the locale to English to get RFC2616 HTTP dates with English day names.
  // Also set to utf8 because libxml will output utf8 strings.
  if (!setlocale(LC_ALL, "en_US.utf8"))
    throw runtime_error("Could not set the locale to english. Needed for authentication.");

  // The text that we will process
  string query = "[{\"lemma\": \"Montréal\", \"fsk\": [{ \"fsk\": null, \"definition\": null, \"extRefs\": [], \"neInfo\": null }] }]";
  string resource = "/1/kb/query.json";
  string url = string("http://api.idilia.com") + resource;

  // Get a CURL handle for the request.
  CURL * curl = curl_easy_init();
  if (!curl)
    throw std::runtime_error("Could not obtain CURL handle");

  // Parameters for the request
  map<string, string> parms;
  parms["requestId"] = "my-request";
  parms["pretty"] = "1";
  parms["query"] = query;
  string encParms = convertToQueryParms(curl, parms);

  curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
  curl_easy_setopt(curl, CURLOPT_POSTFIELDS, encParms.c_str());

  // Setup to recover the downloaded content in a string that acts as a buffer
  string response;
  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, curlCallback);
  curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);

  // setup headers for authentication
  struct curl_slist *headers=NULL;
  headers = curl_slist_append(headers, "Expect:"); // Don't wait for this
  headers = curl_slist_append(headers, "Content-Type: application/x-www-form-urlencoded; charset=UTF-8");
  headers = addSignature("api.idilia.com", resource, query.c_str(), query.length(), headers);
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
  if (httpCode != 200)
  {
    stringstream ss; ss << httpCode << ' ' << response;
    throw std::runtime_error(ss.str());
  }

  // Cleanup
  curl_easy_cleanup(curl);
  curl_slist_free_all(headers);

  // The response to this operation is a JSON object which you can parse with your
  // favorite JSON library.
  cerr << "Got JSON response\n" << response << endl;

  // Global cleanup done once
  curl_global_cleanup();
  return 0;
}
