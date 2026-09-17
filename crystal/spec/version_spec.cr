# version_spec.cr — drift guard for the pinned engine release tag.
#
# Crystal's @[Link(ldflags:)] must be a STRING LITERAL, so this binding bakes
# SELENIUM_CORE_VERSION as a literal in src/selenium.cr rather than reading the
# repo-root SELENIUM_CORE_VERSION file at build time (the way most bindings do).
# This spec reads that source-of-truth file and fails if the literal drifts from
# it, so the two cannot silently diverge. Do NOT "fix" a failure here by editing
# the file to match — update SELENIUM_CORE_VERSION in src/selenium.cr instead.
require "spec"
require "../src/selenium"

describe "SELENIUM_CORE_VERSION pin" do
  it "matches the repo-root SELENIUM_CORE_VERSION" do
    # spec is at crystal/spec/, so ../.. is the repo root.
    path = File.join(__DIR__, "..", "..", "SELENIUM_CORE_VERSION")
    want = File.read(path).strip
    # SELENIUM_CORE_VERSION is a top-level constant in src/selenium.cr (defined before
    # `module Selenium`), so it is referenced bare, not as Selenium::SELENIUM_CORE_VERSION.
    SELENIUM_CORE_VERSION.should eq(want)
  end
end
