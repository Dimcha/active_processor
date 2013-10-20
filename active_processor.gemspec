$:.push File.expand_path("../lib", __FILE__)
require "active_processor/version"

Gem::Specification.new do |s|
  s.name        = 'active_processor'
  s.version     = ActiveProcessor::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ['Kolmisoft']
  s.email       = ['info@kolmisoft.com']
  s.homepage    = 'https://example.com/active_proce.ssor'
  s.summary     = 'Payment gateway wrapper'
  s.description = 'Extensible payment gateway wrapper'
  s.licenses = ['MIT']
  s.rubyforge_project = 'active_processor'

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {tests}/*`.split("\n")
  s.extra_rdoc_files = ['README']
  s.require_paths = ['lib']

  s.add_dependency 'railties', '>= 3.0.0'
  s.add_dependency 'activemerchant', '1.5.0'
  s.add_dependency 'google4r-checkout', '1.0.6'
  s.add_dependency 'ideal', '0.2.0'
  s.add_development_dependency 'shoulda'
  s.add_development_dependency 'mocha'
end
