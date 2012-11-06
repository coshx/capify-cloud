# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)

Gem::Specification.new do |s|
  s.name        = "capify-cloud"
  s.version     = '01'
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Noah Cantor"]
  s.email       = ["ncantor@gmail.com"]
  s.homepage    = "http://github.com/ncantor/capify-cloud"
  s.summary     = %q{Grabs roles from clouds' meta-data and autogenerates capistrano tasks}
  s.description = %q{Grabs roles from clouds' meta-data and autogenerates capistrano tasks}

  s.rubyforge_project = "capify-cloud"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
  s.add_dependency('colored', '=1.2')
  s.add_dependency('capistrano')
  s.add_dependency('fog')
  s.add_development_dependency "rspec"
end
