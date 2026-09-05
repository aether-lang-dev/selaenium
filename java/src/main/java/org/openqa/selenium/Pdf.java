package org.openqa.selenium;

import java.util.Base64;

/**
 * A rendered PDF returned by {@link PrintsPage#print}. Wraps the base64-encoded
 * document exactly as mainstream Selenium's {@code org.openqa.selenium.Pdf}.
 */
public class Pdf {

  private final String base64EncodedPdf;

  public Pdf(String base64EncodedPdf) {
    this.base64EncodedPdf = base64EncodedPdf;
  }

  /** The base64-encoded PDF content (the raw print/PDF endpoint payload). */
  public String getContent() {
    return base64EncodedPdf;
  }

  /** The decoded PDF bytes. */
  public byte[] getBytes() {
    return Base64.getDecoder().decode(base64EncodedPdf);
  }
}
