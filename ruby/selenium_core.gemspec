# frozen_string_literal: true

require_relative 'lib/selenium_core'

Gem::Specification.new do |spec|
  spec.name        = 'selenium_core'
  spec.version     = SeleniumCore::VERSION
  spec.summary     = 'Selenium WebDriver for Ruby — a thin Fiddle wrapper over the shared pure-Aether WebDriver core'
  spec.description  = 'Re-glues the Ruby WebDriver surface to the one shared ' \
                      'pure-Aether engine (libselenium_core.so). Carries no ' \
                      'protocol logic; the W3C command map, routing, By ' \
                      'normalization, error decode and HTTP round-trip all live ' \
                      'in the shared engine.'
  spec.authors     = ['Paul Hammant']
  spec.email       = ['paul@hammant.org']
  spec.homepage    = 'https://github.com/SeleniumHQ/selenium'
  spec.license     = 'Apache-2.0'
  spec.required_ruby_version = '>= 3.0'

  # Sweep in the whole lib tree — including the bundled engine .so under
  # lib/selenium_core/native/ that .package.ae stages before `gem build`.
  spec.files = Dir['lib/**/*'] + ['README.md'].select { |f| File.exist?(f) }
  spec.require_paths = ['lib']

  # No runtime gem dependencies: the binding uses only the stdlib (Fiddle + json).
end
