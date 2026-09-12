"""Virtual-authenticator (WebAuthn) types, at the Selenium 4.x import path
``from selenium.webdriver.common.virtual_authenticator import ...``.

Re-exports the types from the binding core. The commands themselves live on
:class:`~selenium.webdriver.remote.webdriver.WebDriver`
(``add_virtual_authenticator`` and friends).
"""

from ..._webdriver import Credential, Protocol, Transport, VirtualAuthenticatorOptions

__all__ = ["Credential", "Protocol", "Transport", "VirtualAuthenticatorOptions"]
