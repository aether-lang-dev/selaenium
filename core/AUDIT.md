# Native capability audit

The `selenium_core/.build.ae` target grants `net,os,fs,extern` to the Aether
shared-library build. This records the capabilities needed by the compiled
library; it does not sandbox the resulting `.so` when a host such as Java loads
it. The operations below are source-level uses in the library's build graph;
they do not all run on every use.

## `net`

The core sends WebDriver HTTP requests to a driver or Grid, fetches browser and
driver metadata and archives, and can connect to a WebDriver-BiDi WebSocket.
Those paths use Aether's HTTP client, including request creation, headers and
bodies, timeouts, redirect and proxy settings, sending requests, reading
responses, and freeing request/response objects. The driver and browser
downloads are written into the local cache after retrieval.

The core also uses `net.http_server_create`, `net.http_server_bind_raw`,
`net.http_server_port`, `net.http_server_free`, `net.tcp_connect_raw`, and
`net.tcp_close` to select and check an available localhost port. The optional
runner server listens for HTTP and WebSocket connections; its handlers send,
receive, and close WebSocket messages. The network capability therefore
covers outbound HTTP(S)/WebSocket traffic and optional inbound listening.

## `os`

The driver manager reads environment variables for browser and driver paths,
proxy, cache location, versions, timeouts, and runner configuration. It uses
`os.which` to locate executables and `os.exec` to run `uname -s` and `uname -m`
for platform detection.

It also runs commands and launches programs. `os.run_capture` invokes browser
and driver version probes, cache download and archive-unpack commands, and
helper processes. `os.spawn_proc` starts driver processes; `os.kill`,
`os.wait_any_timeout`, and `os.wait` manage their shutdown. In practical terms,
the grant includes arbitrary subprocess execution through `run_capture` and
`exec`, as well as starting and controlling browser and driver processes.

## `fs`

The driver manager checks whether candidate browser and driver files exist,
creates cache directories, and reads and writes driver-version metadata. When
it provisions a browser or driver, it writes the downloaded archive, removes
temporary archives and staging files, and changes the extracted executable's
permissions with `fs.chmod`. The relevant operations include `file.exists`,
`file.read`, `file.write`, `fs.exists`, `fs.mkdir_p`, `fs.write_binary`, and
`fs.chmod`. Archive extraction and some cleanup are performed by subprocesses
under the `os` grant, rather than by Aether filesystem calls.

## `extern`

The core declares two C functions: `sel_embed_dup` and `sel_embed_free`. They
are implemented in `selenium_core/_embed_strdup.c`. `sel_embed_dup` allocates a
NUL-terminated copy of a string for the FFI host to own; `sel_embed_free` frees
that allocation. This is the caller-owned-string bridge used by the bindings.
The core's own declared externs are limited to these two functions.

## Source references

- Capability grants: [`selenium_core/.build.ae`](../selenium_core/.build.ae)
- C declarations: [`selenium_core/embed.ae`](../selenium_core/embed.ae)
- C implementation: [`selenium_core/_embed_strdup.c`](../selenium_core/_embed_strdup.c)
- HTTP and WebDriver requests: [`selenium_core/selenium_core.ae`](../selenium_core/selenium_core.ae)
- Process lifecycle and local port probing: [`selenium_core/driver.ae`](../selenium_core/driver.ae)
- Driver manager and cache: [`selenium_core/drivermgr/`](../selenium_core/drivermgr/)
- BiDi WebSocket client: [`selenium_core/selenium_bidi.ae`](../selenium_core/selenium_bidi.ae)
- Optional runner server: [`selenium_core/runner_server.ae`](../selenium_core/runner_server.ae)
