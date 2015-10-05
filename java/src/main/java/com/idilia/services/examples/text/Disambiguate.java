package com.idilia.services.examples.text;
/*
 * Example program to issue a text/disambiguate request.
 */

import java.io.IOException;
import java.io.UnsupportedEncodingException;
import java.nio.charset.StandardCharsets;

import javax.mail.MessagingException;
import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;

import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.NodeList;
import org.xml.sax.InputSource;
import org.xml.sax.SAXException;

import com.idilia.services.base.IdiliaClientException;
import com.idilia.services.base.IdiliaCredentials;
import com.idilia.services.text.Client;
import com.idilia.services.text.DisambiguateRequest;
import com.idilia.services.text.DisambiguateResponse;
import com.idilia.services.text.DisambiguatedDocument;


public class Disambiguate {

    public static void main(String[] args) throws IOException, MessagingException, SAXException, UnsupportedEncodingException {
    	
      IdiliaCredentials creds = new IdiliaCredentials(accessKey, privateKey);

      // Create the request
      DisambiguateRequest disReq = new DisambiguateRequest();
      disReq.setRequestId("test");
      disReq.setText("JFK was shot in Dallas.", "text/plain", StandardCharsets.UTF_8);

      try (Client txtClient = new Client(creds)) {
        
        DisambiguateResponse disResp = txtClient.disambiguate(disReq);
        DisambiguatedDocument dDoc = disResp.getResult();
        
        InputSource src = new InputSource(dDoc.getInputStream());
        Document semDoc = docBuilder.parse(src);
        
        // Display all the tagged senses
        System.out.println("Found senses:");
        NodeList fss = semDoc.getElementsByTagName("fs");
        for (int fsIdx = 0; fsIdx < fss.getLength(); ++fsIdx) {
          Element fs = (Element) fss.item(fsIdx);
          String sk = fs.getAttribute("sk");
          System.out.println("  " + sk);
        }
      } catch (IdiliaClientException ice) {
        System.err.println("Caught unexpected exception: " + ice.getMessage());
      }
    }
    
    // The credentials obtained from https://www.idilia.com/developer/my-projects
    private static final String accessKey = System.getenv("IDILIA_ACCESS_KEY");
    private static final String privateKey = System.getenv("IDILIA_PRIVATE_KEY");
    
    private static DocumentBuilder docBuilder;
    
    static {
      // Compile the variables that can throw exceptions
      try {
        docBuilder = DocumentBuilderFactory.newInstance().newDocumentBuilder();
      } catch (Exception e) {
        e.printStackTrace();
      }
    }
}