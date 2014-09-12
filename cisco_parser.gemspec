# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'cisco_parser/version'

Gem::Specification.new do |spec|
  spec.name = "cisco_parser"
  spec.version = CiscoParser::VERSION
  spec.authors = ["Roman Priesol"]
  spec.email = ["roman@priesol.net"]
  spec.summary = %q{A parser for Cisco show commands}
  spec.description = %q{cisco_parser can take complete listing of show commands (e.g. from rancid) and parse only a particular output of a show command from it.}
  spec.homepage = "http://github.com/randybb/cisco_parser"
  spec.license = "MIT"

  spec.files = `git ls-files -z`.split("\x0")
  spec.executables = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.7"
  spec.add_development_dependency "rake", "~> 10.0"
end
