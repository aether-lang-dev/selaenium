// Standalone content server for the live surface test. Runs in its OWN process
// because the binding's FFI calls are synchronous and block the Node event loop
// — a server in the same process could not respond while a d.get() blocks (the
// browser would be fetching from a frozen event loop). Prints "PORT <n>" on
// stdout once listening, then serves until killed.
'use strict'

const http = require('node:http')

const PAGE_ONE =
  '<!doctype html><title>Page One</title><h1 id="hdr">One</h1>' +
  '<a id="go" href="/two">to two</a>' +
  "<button id=\"btn\" onclick=\"document.getElementById('hdr').textContent='clicked'\">b</button>"
const PAGE_TWO = '<!doctype html><title>Page Two</title><h1 id="hdr">Two</h1>'

const server = http.createServer((req, res) => {
  res.setHeader('Content-Type', 'text/html; charset=utf-8')
  res.end(req.url.startsWith('/two') ? PAGE_TWO : PAGE_ONE)
})

server.listen(0, '127.0.0.1', () => {
  process.stdout.write(`PORT ${server.address().port}\n`)
})
