package com.idilia.services.examples.text;
/*
 * Example program to issue a text/paraphrase request.
 */

import java.nio.charset.StandardCharsets;

import com.idilia.services.base.IdiliaClientException;
import com.idilia.services.base.IdiliaCredentials;
import com.idilia.services.text.Client;
import com.idilia.services.text.ParaphraseRequest;
import com.idilia.services.text.ParaphraseResponse;


public class Paraphrase {

  public static void main(String[] args) {

    IdiliaCredentials creds = new IdiliaCredentials(accessKey, privateKey);

    // Create the request
    String text = "porch lights";
    ParaphraseRequest paraReq = new ParaphraseRequest();
    paraReq.setText(text, "text/query", StandardCharsets.UTF_8);
    paraReq.setRequestId("test");
    paraReq.setParaphrasingRecipe("productSearch");
    paraReq.setMaxCount(10);

    try (Client txtClient = new Client(creds)) {
      ParaphraseResponse paraResp = txtClient.paraphrase(paraReq);

      Double ccfmp = paraResp.getQueryConfidence().confCorrectFineMostProbable;
      System.out.format("Paraphrases received for query [%s] (overall conf: %.2f)\n", text, ccfmp);
      for (ParaphraseResponse.Paraphrase para: paraResp.getParaphrases()) {
        System.out.format("  [%s] with weight %.2f\n", para.getSurface(), para.getWeight());
      }
    } catch (IdiliaClientException ice) {
      System.err.println("Caught unexpected exception: " + ice.getMessage());
    }
  }


  // The credentials obtained from https://www.idilia.com/developer/my-projects
  private static final String accessKey = System.getenv("IDILIA_ACCESS_KEY");
  private static final String privateKey = System.getenv("IDILIA_PRIVATE_KEY");
}
