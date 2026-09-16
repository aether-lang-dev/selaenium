# frozen_string_literal: true

# Unit test for the engine fetcher — the `rake selenium:fetch_engine` machinery
# that lets a Ruby dev get the prebuilt pure-Aether engine from GitHub releases
# with no Aether toolchain. The pure logic (asset naming, cache path, platform
# mapping, the version pin) needs no network. One live download test is gated on
# SELENIUM_FETCH_LIVE=1 so the default suite stays offline/deterministic.

require 'minitest/autorun'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'selenium-webdriver'

class EngineFetcherTest < Minitest::Test
  F = Selenium::WebDriver::EngineFetcher

  def test_engine_version_is_a_release_tag
    assert_match(/\Av\d+\.\d+\.\d+\z/, F::ENGINE_VERSION, 'ENGINE_VERSION is a vX.Y.Z gh-release tag')
    assert_equal F::ENGINE_VERSION, Selenium::WebDriver::ENGINE_VERSION, 're-exported on the top module'
  end

  def test_asset_name_matches_the_release_artifact_scheme
    # libselenium_core-<tag>-<os>-<arch>.<ext> — exactly what release/build.sh emits.
    assert_match(
      %r{\Alibselenium_core-v\d+\.\d+\.\d+-(linux|macos|windows)-(x86_64|arm64)\.(so|dylib|dll)\z},
      F.asset_name
    )
  end

  def test_cached_path_is_under_the_cache_dir_keyed_by_tag
    path = F.cached_path
    assert path.start_with?(F.cache_dir), 'cached under the cache dir'
    assert_includes path, F::ENGINE_VERSION, 'keyed by the engine tag (survives gem upgrades)'
    assert_equal F.library_filename, File.basename(path), 'bare library filename the loader looks for'
  end

  def test_platform_mapping_is_total_for_this_host
    # os_tag/arch_tag/ext must not raise on the host running the suite.
    assert %w[linux macos windows].include?(F.os_tag)
    assert %w[x86_64 arm64].include?(F.arch_tag)
    assert %w[so dylib dll].include?(F.ext)
  end

  def test_loader_looks_in_the_fetch_cache
    # Native's candidate list must include exactly where the fetcher caches, so a
    # fetched engine loads with no further config.
    cands = Selenium::WebDriver::Native.library_candidates
    assert_includes cands, F.cached_path
  end

  def test_live_fetch_downloads_and_verifies
    skip 'set SELENIUM_FETCH_LIVE=1 to hit the network' unless ENV['SELENIUM_FETCH_LIVE'] == '1'
    require 'tmpdir'
    require 'digest'
    Dir.mktmpdir do |dir|
      ENV['XDG_CACHE_HOME'] = dir
      path = Selenium::WebDriver.fetch_engine!(force: true)
      assert File.file?(path), 'engine downloaded to the cache'
      assert File.size(path).positive?, 'non-empty'
      want = F.expected_sha
      assert_equal want, Digest::SHA256.hexdigest(File.binread(path)), 'matches the published .sha256' if want
    end
  ensure
    ENV.delete('XDG_CACHE_HOME')
  end
end
