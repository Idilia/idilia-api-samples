package com.idilia.services.examples.menu;

import java.nio.charset.StandardCharsets;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;

import com.idilia.services.base.IdiliaCredentials;
import com.idilia.services.kb.TaggingMenuRequest;
import com.idilia.services.kb.TaggingMenuResponse;
import com.idilia.services.text.DisambiguateRequest;

/**
 * Example of using the API asynchronous clients to obtain a tagging menu.
 */
public class TaggingMenuAsync {

  public static void main(String[] args) {

    IdiliaCredentials creds = new IdiliaCredentials(accessKey, privateKey);

    /* Create the disambiguate request with the text to put in the menu.
     * The key here is the resultMime expected by the tagging menu API 
     */
    DisambiguateRequest disReq = new DisambiguateRequest();
    disReq.setText("jaguar jungle food", "text/plain", StandardCharsets.UTF_8);
    disReq.setResultMime("application/x-tf+xml+gz");

    /* Instantiate the two clients that we need. 
     * These can be re-used between requests and with simultaneous requests.
     * Here we'll just use them once.
     */
    com.idilia.services.text.AsyncClient txClient = new com.idilia.services.text.AsyncClient(creds);
    com.idilia.services.kb.AsyncClient kbClient = new com.idilia.services.kb.AsyncClient(creds);

    /* Create a future that is marked complete upon all processing */
    CompletableFuture<TaggingMenuResponse> tmFuture = 

        /* First stage obtains the results from sense analysis */
        txClient.disambiguateAsync(disReq).thenCompose(disResp -> {

          /* Second stage obtains the tagging menu response */
          TaggingMenuRequest menuReq = new TaggingMenuRequest();
          menuReq.
            setTf(disResp.getResult()).
            setTemplate("image_v3").
            setFilters("noDynamic");
          return kbClient.taggingMenuAsync(menuReq);
          
        }).whenComplete((tmResp, ex) -> {
          /* A cleanup of resources */
          txClient.close();
          kbClient.close();
        });

    /* Wait for the future to complete and then print the response */
    try {
      TaggingMenuResponse tmResp = tmFuture.get();
      System.out.println("Got HTML for words: " + tmResp.text);
      System.out.format("Got HTML for menus: %d characters\n", tmResp.menu.length());
    } catch (ExecutionException ee) {
      System.err.println("Got exception: " + ee.getCause().getMessage());
    } catch (InterruptedException ie) {
      System.err.println("Got exception: " + ie.getMessage());
    }
    
    /* 
     * We're done with asynchronous processing. Shutdown the HTTP client. 
     * Only need to do this once on program exit for all Idilia's clients instances.
     */
    com.idilia.services.base.AsyncClientBase.stop();
  }

  // The credentials obtained from https://www.idilia.com/developer/my-projects
  private static final String accessKey = System.getenv("IDILIA_ACCESS_KEY");
  private static final String privateKey = System.getenv("IDILIA_PRIVATE_KEY");
}
