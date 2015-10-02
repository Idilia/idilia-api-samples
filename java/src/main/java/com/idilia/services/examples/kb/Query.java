package com.idilia.services.examples.kb;

/*
 * Example program to issue a kb/query request.
 */

import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import com.idilia.services.base.IdiliaClientException;
import com.idilia.services.base.IdiliaCredentials;
import com.idilia.services.kb.Client;
import com.idilia.services.kb.QueryRequest;
import com.idilia.services.kb.QueryResponse;
import com.idilia.services.kb.objects.NeInfo;

public class Query {

  public static void main(String[] args) {

    IdiliaCredentials creds = new IdiliaCredentials(accessKey, privateKey);

    // Create the request. It asks for the LemmaInfo for two words.
    // The request is converted from Java to JSON and sent
    // to the server. The response is then recovered from JSON and converted
    // to Java objects.
    QueryRequest kbReq = new QueryRequest(
        Arrays.asList(LemmaInfo.query("dog"), LemmaInfo.query("cat")));
    
    try (Client kbClient = new Client(creds)) {
      
      QueryResponse<LemmaInfo> kbResp = kbClient.query(kbReq, LemmaInfo.class);

      for (LemmaInfo li: kbResp.getResult()) {
        System.out.format("Result for lemma: %s\n", li.lemma);
        for (LemmaInfo.FskInfo fi: li.fsk) {
          System.out.format("Fsk: %s has parent(s) %s\n", fi.fsk, fi.parents.toString());
        }
        System.out.println("");
      }
    } catch (IdiliaClientException ice) {
      System.err.println("Caught unexpected exception: " + ice.getMessage());
    }
  }

  /**
   * Class that we use for json serialization/deserialization into a java POJO
   */
  public static class LemmaInfo {

    /**
     * We need to create an instance that represents the query. Result arrays
     * must be initialized to one instance of a complex expansion or an empty
     * array that will be populated with the default expansion.
     */
    static LemmaInfo query(String lemma) {
      LemmaInfo li = new LemmaInfo();
      li.lemma = lemma;
      /* specifies a template for custom expansion */
      li.fsk = Collections.singletonList(FskInfo.query());
      return li;
    }

    /**
     * Fields of the query and response. The name of the properties must match
     * the API properties. This outer level definition expands a lemma into its
     * sensekeys.
     */
    
    /** this field is populated with a lemma for queries */
    public String lemma; 
    
    /** this field is expanded by the server */
    public List<FskInfo> fsk; 

    /**
     * This is an inner class for returning several properties of the sense keys
     * of the lemma
     */
    public static class FskInfo {
      public String fsk;
      public List<String> parents;
      public NeInfo neInfo;
      public List<String> children;

      static FskInfo query() {
        FskInfo fi = new FskInfo();
        /* empty arrays to use the default expansion for these */
        fi.parents = fi.children = Collections.emptyList(); 
        return fi;
      }
    };

  }

  // The credentials obtained from https://www.idilia.com/developer/my-projects
  private static final String accessKey = System.getenv("IDILIA_ACCESS_KEY");
  private static final String privateKey = System.getenv("IDILIA_PRIVATE_KEY");
}