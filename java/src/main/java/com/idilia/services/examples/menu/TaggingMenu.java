package com.idilia.services.examples.menu;

import java.nio.charset.StandardCharsets;

import com.idilia.services.base.IdiliaClientException;
import com.idilia.services.base.IdiliaCredentials;
import com.idilia.services.kb.TaggingMenuRequest;
import com.idilia.services.kb.TaggingMenuResponse;
import com.idilia.services.text.DisambiguateRequest;
import com.idilia.services.text.DisambiguateResponse;

/**
 * Example of using the API asynchronous clients to obtain a tagging menu.
 */
public class TaggingMenu {

  public static void main(String[] args) {

    IdiliaCredentials creds = new IdiliaCredentials(accessKey, privateKey);

    /* 
     * Create the disambiguate request with the text to put in the menu.
     * The key here is the resultMime expected by the tagging menu API 
     */
    DisambiguateRequest disReq = new DisambiguateRequest();
    disReq.setText("jaguar jungle food", "text/plain", StandardCharsets.UTF_8);
    disReq.setResultMime("application/x-tf+xml+gz");

    /* Instantiate the two clients that we need. 
     * These can be re-used between requests and with simultaneous requests.
     * Here we'll just use them once.
     */
    try (
      com.idilia.services.text.Client txClient = new com.idilia.services.text.Client(creds);
      com.idilia.services.kb.Client kbClient = new com.idilia.services.kb.Client(creds)) {
      
      /* First get the sense analysis results */
      DisambiguateResponse disResp = txClient.disambiguate(disReq);
      
      /* Now send those to the tagging menu API to obtain the tagging menu */
      TaggingMenuRequest menuReq = new TaggingMenuRequest();
      menuReq.
        setTf(disResp.getResult()).
        setTemplate("image_v3").
        setFilters("noDynamic");
      TaggingMenuResponse tmResp = kbClient.taggingMenu(menuReq);
      
      System.out.println("Got HTML for words: " + tmResp.text);
      System.out.format("Got HTML for menus: %d characters\n", tmResp.menu.length());
      
    } catch (IdiliaClientException ice) {
      System.err.println("Got exception: " + ice.getMessage());
    }
  }

  // The credentials obtained from https://www.idilia.com/developer/my-projects
  private static final String accessKey = System.getenv("IDILIA_ACCESS_KEY");
  private static final String privateKey = System.getenv("IDILIA_PRIVATE_KEY");
}
