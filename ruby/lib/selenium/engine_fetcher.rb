# frozen_string_literal: true

require 'rbconfig'
require 'fileutils'
require 'digest'
require 'net/http'
require 'uri'

module Selenium
  module WebDriver
    # Fetches the prebuilt pure-Aether engine (+libselenium_core+) from the
    # project's GitHub releases and caches it, so a Ruby dev never needs the
    # Aether toolchain: +gem install selenium-webdriver+ ships no engine, then
    #
    #   rake selenium:fetch_engine        # or Selenium::WebDriver.fetch_engine!
    #
    # downloads the right +.so+/+.dylib+/+.dll+ for this OS+arch, verifies its
    # published +.sha256+, and drops it in the per-user cache where {Native}'s
    # loader already looks. Explicit, one-time, opt-in — no download happens
    # behind the dev's back at +require+ or +gem install+ time.
    #
    # Stdlib only (net/http + digest + fileutils), matching the gem's zero-
    # runtime-dependency contract.
    module EngineFetcher
      module_function

      # The engine release this gem targets. It tracks the gh-release TAG of the
      # shared engine (NOT the gem's own VERSION) — that is the tag whose assets
      # this fetcher downloads. Bump it when the gem is re-glued to a newer engine.
      ENGINE_VERSION = 'v0.8.0'

      REPO = 'aether-lang-dev/selaenium'

      # +GET https://github.com/<repo>/releases/download/<tag>/<asset>+ — the
      # public, unauthenticated asset URL gh release create publishes to.
      RELEASE_BASE = "https://github.com/#{REPO}/releases/download"

      class FetchError < StandardError; end

      # Download (unless already cached + verified) the engine for this platform
      # and return the absolute path to the cached library. Idempotent: a present,
      # checksum-matching cached copy is returned without a network call. +tag+
      # overrides {ENGINE_VERSION} (e.g. to pin an older engine); +force+ re-fetches.
      def fetch!(tag: ENGINE_VERSION, force: false)
        dest = cached_path(tag)
        return dest if !force && File.file?(dest) && checksum_ok?(dest, expected_sha(tag))

        FileUtils.mkdir_p(File.dirname(dest))
        asset = asset_name(tag)
        url   = "#{RELEASE_BASE}/#{tag}/#{asset}"
        body  = download(url)

        want = expected_sha(tag)
        got  = Digest::SHA256.hexdigest(body)
        raise FetchError, "checksum mismatch for #{asset}: expected #{want}, got #{got}" if want && got != want

        # Write atomically so a half-written file is never left where the loader
        # would try to dlopen it.
        tmp = "#{dest}.#{Process.pid}.part"
        File.binwrite(tmp, body)
        File.rename(tmp, dest)
        dest
      end

      # The absolute path the fetched engine is cached at (whether or not it
      # exists yet) — this is exactly the path {Native.library_candidates} adds,
      # so a fetched engine is found on the next load with no further config.
      def cached_path(tag = ENGINE_VERSION)
        File.join(cache_dir, tag, library_filename)
      end

      # +$XDG_CACHE_HOME/selaenium+ (or the OS default): ~/.cache/selaenium on
      # Linux, ~/Library/Caches/selaenium on macOS, %LOCALAPPDATA%\selaenium on
      # Windows. Kept separate from the gem so it survives gem upgrades/reinstalls.
      def cache_dir
        base =
          if (xdg = ENV['XDG_CACHE_HOME']) && !xdg.empty?
            xdg
          elsif RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
            ENV['LOCALAPPDATA'] || File.join(Dir.home, 'AppData', 'Local')
          elsif RbConfig::CONFIG['host_os'] =~ /darwin/
            File.join(Dir.home, 'Library', 'Caches')
          else
            File.join(Dir.home, '.cache')
          end
        File.join(base, 'selaenium')
      end

      # The gh-release asset for this platform, e.g.
      # +libselenium_core-v0.8.0-linux-x86_64.so+.
      def asset_name(tag = ENGINE_VERSION)
        "libselenium_core-#{tag}-#{os_tag}-#{arch_tag}.#{ext}"
      end

      # The local filename the loader looks for (bare +libselenium_core.<ext>+,
      # no tag/platform — the cache dir already keys by tag).
      def library_filename
        case RbConfig::CONFIG['host_os']
        when /mswin|mingw|cygwin/ then 'selenium_core.dll'
        when /darwin/             then 'libselenium_core.dylib'
        else                           'libselenium_core.so'
        end
      end

      # --- platform mapping (matches release/build.sh's artifact names) ---

      def os_tag
        case RbConfig::CONFIG['host_os']
        when /mswin|mingw|cygwin/ then 'windows'
        when /darwin/             then 'macos'
        when /linux/              then 'linux'
        else raise FetchError, "unsupported OS for a prebuilt engine: #{RbConfig::CONFIG['host_os']}"
        end
      end

      def arch_tag
        case RbConfig::CONFIG['host_cpu']
        when /x86_64|x64|amd64/     then 'x86_64'
        when /arm64|aarch64/        then 'arm64'
        else raise FetchError, "unsupported CPU for a prebuilt engine: #{RbConfig::CONFIG['host_cpu']}"
        end
      end

      def ext
        case RbConfig::CONFIG['host_os']
        when /mswin|mingw|cygwin/ then 'dll'
        when /darwin/             then 'dylib'
        else                           'so'
        end
      end

      # --- helpers ---

      # Fetch the published +<asset>.sha256+ sidecar (a "<hex>  <name>" line) and
      # return the hex. Returns nil if the sidecar can't be fetched — the caller
      # then downloads without a checksum gate rather than failing hard, but a
      # present sidecar is always enforced.
      def expected_sha(tag = ENGINE_VERSION)
        line = download("#{RELEASE_BASE}/#{tag}/#{asset_name(tag)}.sha256")
        line.to_s.strip.split(/\s+/).first
      rescue FetchError
        nil
      end

      def checksum_ok?(path, want)
        return false unless want
        Digest::SHA256.hexdigest(File.binread(path)) == want
      end

      # GET a URL, following GitHub's redirect to the asset CDN. Binary-safe.
      def download(url, limit: 5)
        raise FetchError, "too many redirects fetching #{url}" if limit <= 0

        uri = URI.parse(url)
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
          http.open_timeout = 30
          http.read_timeout = 120
          http.get(uri.request_uri, 'User-Agent' => "selaenium-ruby/#{VERSION}")
        end

        case res
        when Net::HTTPSuccess     then res.body
        when Net::HTTPRedirection then download(res['location'], limit: limit - 1)
        else raise FetchError, "GET #{url} -> #{res.code} #{res.message}"
        end
      end
    end
  end
end
