"""Proxy configuration, at the Selenium 4.x import path
``from selenium.webdriver.common.proxy import Proxy, ProxyType``.

``Proxy`` accumulates the W3C proxy fields and renders them with
``to_capabilities()`` into the ``proxy`` capability the remote end expects.
Assigning ``options.proxy = Proxy(...)`` writes that block into the caps.
"""
from __future__ import annotations


class ProxyTypeFactory:
    """Builds the ``{ff_value, string}`` descriptors ``ProxyType`` is made of."""

    @staticmethod
    def make(ff_value, string):
        return {"ff_value": ff_value, "string": string}


class ProxyType:
    """The proxy kinds a session can request. ``string`` is what goes on the
    wire (lowercased) as ``proxyType``."""

    DIRECT = ProxyTypeFactory.make(0, "DIRECT")  # direct connection, no proxy
    MANUAL = ProxyTypeFactory.make(1, "MANUAL")  # fixed proxy hosts
    PAC = ProxyTypeFactory.make(2, "PAC")  # proxy autoconfiguration URL
    RESERVED_1 = ProxyTypeFactory.make(3, "RESERVED1")  # reserved
    AUTODETECT = ProxyTypeFactory.make(4, "AUTODETECT")  # WPAD autodetection
    SYSTEM = ProxyTypeFactory.make(5, "SYSTEM")  # the OS proxy settings
    UNSPECIFIED = ProxyTypeFactory.make(6, "UNSPECIFIED")  # not set

    @classmethod
    def load(cls, value):
        """Resolve a raw ``proxyType`` (dict or name) to one of the constants."""
        if isinstance(value, dict) and "string" in value:
            value = value["string"]
        value = str(value).upper()
        for attr in dir(cls):
            attr_value = getattr(cls, attr)
            if isinstance(attr_value, dict) and "string" in attr_value and attr_value["string"] == value:
                return attr_value
        raise ValueError(f"No proxy type is found for {value}")


class Proxy:
    """A proxy configuration rendered into the W3C ``proxy`` capability."""

    proxyType = ProxyType.UNSPECIFIED
    autodetect = False
    ftpProxy = ""
    httpProxy = ""
    noProxy = ""
    proxyAutoconfigUrl = ""
    sslProxy = ""
    socksProxy = ""
    socksUsername = ""
    socksPassword = ""
    socksVersion = None

    def __init__(self, raw: dict | None = None):
        if raw is None:
            return
        if not isinstance(raw, dict):
            raise TypeError(f"`raw` must be a dict, got {type(raw)}")
        mapping = {
            "proxyType": "proxy_type",
            "httpProxy": "http_proxy",
            "noProxy": "no_proxy",
            "proxyAutoconfigUrl": "proxy_autoconfig_url",
            "sslProxy": "ssl_proxy",
            "autodetect": "auto_detect",
            "socksProxy": "socks_proxy",
            "socksUsername": "socks_username",
            "socksPassword": "socks_password",
            "socksVersion": "socks_version",
            "ftpProxy": "ftp_proxy",
        }
        for key, attr in mapping.items():
            if raw.get(key):
                setattr(self, attr, raw[key])

    # ---- typed accessors (mainstream snake_case names) ----
    @property
    def proxy_type(self):
        return self.proxyType

    @proxy_type.setter
    def proxy_type(self, value) -> None:
        self.proxyType = ProxyType.load(value)

    @property
    def auto_detect(self):
        return self.autodetect

    @auto_detect.setter
    def auto_detect(self, value) -> None:
        if not isinstance(value, bool):
            raise ValueError("Autodetect proxy value needs to be a boolean")
        self.autodetect = value
        self.proxyType = ProxyType.AUTODETECT

    @property
    def ftp_proxy(self):
        return self.ftpProxy

    @ftp_proxy.setter
    def ftp_proxy(self, value) -> None:
        self.ftpProxy = value
        self.proxyType = ProxyType.MANUAL

    @property
    def http_proxy(self):
        return self.httpProxy

    @http_proxy.setter
    def http_proxy(self, value) -> None:
        self.httpProxy = value
        self.proxyType = ProxyType.MANUAL

    @property
    def no_proxy(self):
        return self.noProxy

    @no_proxy.setter
    def no_proxy(self, value) -> None:
        self.noProxy = value
        self.proxyType = ProxyType.MANUAL

    @property
    def proxy_autoconfig_url(self):
        return self.proxyAutoconfigUrl

    @proxy_autoconfig_url.setter
    def proxy_autoconfig_url(self, value) -> None:
        self.proxyAutoconfigUrl = value
        self.proxyType = ProxyType.PAC

    @property
    def ssl_proxy(self):
        return self.sslProxy

    @ssl_proxy.setter
    def ssl_proxy(self, value) -> None:
        self.sslProxy = value
        self.proxyType = ProxyType.MANUAL

    @property
    def socks_proxy(self):
        return self.socksProxy

    @socks_proxy.setter
    def socks_proxy(self, value) -> None:
        self.socksProxy = value
        self.proxyType = ProxyType.MANUAL

    @property
    def socks_username(self):
        return self.socksUsername

    @socks_username.setter
    def socks_username(self, value) -> None:
        self.socksUsername = value
        self.proxyType = ProxyType.MANUAL

    @property
    def socks_password(self):
        return self.socksPassword

    @socks_password.setter
    def socks_password(self, value) -> None:
        self.socksPassword = value
        self.proxyType = ProxyType.MANUAL

    @property
    def socks_version(self):
        return self.socksVersion

    @socks_version.setter
    def socks_version(self, value) -> None:
        self.socksVersion = value
        self.proxyType = ProxyType.MANUAL

    def to_capabilities(self) -> dict:
        """The ``proxy`` capability block: proxyType plus every field that is set."""
        proxy_caps = {"proxyType": self.proxyType["string"].lower()}
        for field in (
            "autodetect",
            "ftpProxy",
            "httpProxy",
            "proxyAutoconfigUrl",
            "sslProxy",
            "noProxy",
            "socksProxy",
            "socksUsername",
            "socksPassword",
            "socksVersion",
        ):
            value = getattr(self, field)
            if value:
                proxy_caps[field] = value
        return proxy_caps


__all__ = ["Proxy", "ProxyType", "ProxyTypeFactory"]
