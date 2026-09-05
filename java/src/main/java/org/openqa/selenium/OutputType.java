package org.openqa.selenium;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Base64;

/**
 * How a screenshot is returned by {@link TakesScreenshot#getScreenshotAs(OutputType)}.
 * Mirrors Selenium 4.x's {@code org.openqa.selenium.OutputType}: the engine hands
 * back a base64 PNG; each of {@link #BASE64}, {@link #BYTES} and {@link #FILE}
 * converts it into the requested representation.
 */
public interface OutputType<T> {

  /** Obtain the screenshot as base64 data. */
  OutputType<String> BASE64 =
      new OutputType<String>() {
        @Override
        public String convertFromBase64Png(String base64Png) {
          return base64Png;
        }

        @Override
        public String convertFromPngBytes(byte[] png) {
          return Base64.getEncoder().encodeToString(png);
        }

        @Override
        public String toString() {
          return "OutputType.BASE64";
        }
      };

  /** Obtain the screenshot as raw bytes. */
  OutputType<byte[]> BYTES =
      new OutputType<byte[]>() {
        @Override
        public byte[] convertFromBase64Png(String base64Png) {
          return Base64.getDecoder().decode(base64Png);
        }

        @Override
        public byte[] convertFromPngBytes(byte[] png) {
          return png;
        }

        @Override
        public String toString() {
          return "OutputType.BYTES";
        }
      };

  /** Obtain the screenshot into a temporary file that will be deleted on exit. */
  OutputType<File> FILE =
      new OutputType<File>() {
        @Override
        public File convertFromBase64Png(String base64Png) {
          return save(BYTES.convertFromBase64Png(base64Png));
        }

        @Override
        public File convertFromPngBytes(byte[] data) {
          return save(data);
        }

        private File save(byte[] data) {
          Path tmpFilePath = createScreenshotFile();
          try {
            Files.write(tmpFilePath, data);
          } catch (IOException e) {
            throw new WebDriverException(
                "Failed to create or write screenshot to temporary file: "
                    + tmpFilePath.toAbsolutePath(),
                e);
          }
          File tmpFile = tmpFilePath.toFile();
          tmpFile.deleteOnExit();
          return tmpFile;
        }

        private Path createScreenshotFile() {
          try {
            return Files.createTempFile("screenshot", ".png");
          } catch (IOException e) {
            throw new WebDriverException(
                "Failed to create or write screenshot to temporary file: "
                    + "temporary file could not be created",
                e);
          }
        }

        @Override
        public String toString() {
          return "OutputType.FILE";
        }
      };

  /** Convert the base64 PNG the remote end returned into the target type. */
  T convertFromBase64Png(String base64Png);

  /** Convert raw PNG bytes into the target type. */
  T convertFromPngBytes(byte[] png);
}
