Gem::Specification.new do |s|
  s.name        = 'fawn'
  s.version     = '0.1.0'
  s.licenses    = ['MIT']
  s.summary     = "Minimal web server"
  s.description = "Fawn is minimal mutlti thread web server"
  s.authors     = ["t-saito"]
  s.executables = ["fawn"]
  s.add_runtime_dependency "rack"
end