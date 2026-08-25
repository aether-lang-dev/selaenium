// Licensed to the Software Freedom Conservancy (SFC) under one
// or more contributor license agreements.  See the NOTICE file
// distributed with this work for additional information
// regarding copyright ownership.  The SFC licenses this file
// to you under the Apache License, Version 2.0 (the
// "License"); you may not use this file except in compliance
// with the License.  You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

package org.openqa.selenium.grid.data;

import java.io.Serializable;
import java.util.Comparator;

public class SemanticVersionComparator implements Comparator<String>, Serializable {

  @Override
  public int compare(String v1, String v2) {
    // Custom semver comparator with empty strings last
    if (v1.isEmpty() && v2.isEmpty()) return 0;
    if (v1.isEmpty()) return 1; // Empty string comes last
    if (v2.isEmpty()) return -1;

    String[] parts1 = v1.split("\\.");
    String[] parts2 = v2.split("\\.");

    int maxLength = Math.max(parts1.length, parts2.length);
    for (int i = 0; i < maxLength; i++) {
      String part1 = i < parts1.length ? parts1[i] : "0";
      String part2 = i < parts2.length ? parts2[i] : part1;

      boolean isPart1Numeric = isNumber(part1);
      boolean isPart2Numeric = isNumber(part2);

      if (isPart1Numeric && isPart2Numeric) {
        // Compare numerically
        int num1 = Integer.parseInt(part1);
        int num2 = Integer.parseInt(part2);
        if (num1 != num2) {
          return Integer.compare(num1, num2); // Ascending order
        }
      } else if (!isPart1Numeric && !isPart2Numeric) {
        // Compare lexicographically, case-insensitive
        int result = part1.compareToIgnoreCase(part2); // Ascending order
        if (result != 0) {
          return result;
        }
      } else {
        // Numbers take precedence over strings
        return isPart1Numeric ? 1 : -1;
      }
    }
    return 0; // Versions are equal
  }

  private boolean isNumber(String str) {
    if (str == null || str.isEmpty()) {
      return false;
    }
    for (char c : str.toCharArray()) {
      if (c < '\u0030' || c > '\u0039') {
        return false;
      }
    }
    return true;
  }
}
