For the shared library, these are the `os`, network, filesystem, and C extern
operations I found.

`os` calls:

- **Launch commands and programs:** `os.run_capture` runs browser and driver
  version probes, cache download/unpack commands, and helper processes.
  `os.spawn_proc` starts driver processes. `os.kill`, `os.wait_any_timeout`,
  and `os.wait` manage their shutdown. [driver.ae](driver.ae:164) ·
  [drivercache.ae](drivermgr/drivercache.ae:78)
- **Discover executables and platform:** `os.which` locates Node and drivers;
  `os.exec` runs `uname -s` and `uname -m` for platform detection.
  [resolve.ae](drivermgr/resolve.ae:290)
- **Read environment variables:** `os.getenv` reads browser/driver paths,
  proxy, cache settings, versions, timeouts, and runner configuration.
  [config.ae](drivermgr/config.ae:57)

The direct `net` calls are narrower:

- `net.http_server_create`, `net.http_server_bind_raw`,
  `net.http_server_port`, and `net.http_server_free` find an available
  localhost port; `net.tcp_connect_raw` and `net.tcp_close` check that port.
  [driver.ae](driver.ae:328)
- HTTP client calls send WebDriver commands and fetch driver metadata and
  archives: `client.request`, `set_header`, `set_body`, `set_timeout`,
  `set_follow_redirects`, `use_http_proxy`, `send_request`, and response
  access/free functions. [selenium_core.ae](selenium_core.ae:1360) ·
  [resolve.ae](drivermgr/resolve.ae:269) ·
  [drivercache.ae](drivermgr/drivercache.ae:255)
- BiDi uses `http.ws_connect`, `ws_send_text`, `ws_recv_timeout`,
  `ws_message`, `ws_close`, and `ws_fd`. The optional runner server also
  listens for HTTP and WebSocket connections. [selenium_bidi.ae](selenium_bidi.ae:25) ·
  [runner_server.ae](runner_server.ae:65)

`fs` calls:

- **Find files and manage the cache:** `file.exists` and `fs.exists` check for
  browser, driver, and metadata files; `fs.mkdir_p` creates cache directories.
  [browser.ae](drivermgr/browser.ae:28) ·
  [appium.ae](drivermgr/appium.ae:87) ·
  [metadata.ae](drivermgr/metadata.ae:101)
- **Read and write metadata and downloads:** `file.read` and `file.write`
  access the driver-version metadata; `fs.write_binary` stores downloaded
  browser and driver archives. [metadata.ae](drivermgr/metadata.ae:102) ·
  [drivercache.ae](drivermgr/drivercache.ae:271)
- **Set executable permissions:** `fs.chmod` makes extracted browser and
  driver binaries executable. [drivercache.ae](drivermgr/drivercache.ae:101)

Archive extraction and some temporary-file cleanup run as subprocess commands
under the `os` grant. Together, these filesystem calls let the driver manager
inspect paths and create and modify its local browser/driver cache; they are
source-level uses and do not all run on every use.

`extern` calls:

- The core declares `sel_embed_dup` and `sel_embed_free`, implemented in
  [_embed_strdup.c](_embed_strdup.c). `sel_embed_dup` allocates a
  NUL-terminated string for the FFI host to own; `sel_embed_free` releases it.
  These two functions are the caller-owned-string bridge used by the bindings.
  [embed.ae](embed.ae:57)

So `os` includes arbitrary subprocess execution through `run_capture` and
`exec`, as well as launching and controlling browser processes. The network
use includes outbound HTTP(S)/WebSocket traffic and, when the runner server is
used, inbound listening. `fs` allows the driver manager to inspect and modify
its local cache. The C extern grant is used for the two string-ownership
functions above. These grants describe source-level capabilities in the
library build; they do not sandbox the resulting `.so` when a host such as
Java loads it.
