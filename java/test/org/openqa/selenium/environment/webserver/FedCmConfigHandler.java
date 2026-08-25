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

package org.openqa.selenium.environment.webserver;

import java.io.UncheckedIOException;
import java.util.Map;
import org.openqa.selenium.remote.http.Contents;
import org.openqa.selenium.remote.http.HttpHandler;
import org.openqa.selenium.remote.http.HttpRequest;
import org.openqa.selenium.remote.http.HttpResponse;

class FedCmConfigHandler implements HttpHandler {

  @Override
  public HttpResponse execute(HttpRequest req) throws UncheckedIOException {
    HttpResponse response = new HttpResponse();
    response.setHeader("Content-Type", "application/json");
    response.setHeader("Cache-Control", "no-store");

    response.setContent(
        Contents.asJson(
            Map.of(
                "accounts_endpoint", "accounts.json",
                "client_metadata_endpoint", "client_metadata.json",
                "id_assertion_endpoint", "id_assertion.json",
                "signin_url", "signin",
                "login_url", "login")));

    return response;
  }
}
