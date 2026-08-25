# Licensed to the Software Freedom Conservancy (SFC) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The SFC licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

from selenium.webdriver.common.fedcm.account import Account


def test_account_properties():
    account_data = {
        "accountId": "12341234",
        "email": "test@email.com",
        "name": "Real Name",
        "givenName": "Test Name",
        "pictureUrl": "picture-url",
        "idpConfigUrl": "idp-config-url",
        "loginState": "login-state",
        "termsOfServiceUrl": "terms-of-service-url",
        "privacyPolicyUrl": "privacy-policy-url",
    }

    account = Account(account_data)

    assert account.account_id == "12341234"
    assert account.email == "test@email.com"
    assert account.name == "Real Name"
    assert account.given_name == "Test Name"
    assert account.picture_url == "picture-url"
    assert account.idp_config_url == "idp-config-url"
    assert account.login_state == "login-state"
    assert account.terms_of_service_url == "terms-of-service-url"
    assert account.privacy_policy_url == "privacy-policy-url"
