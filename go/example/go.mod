module selenium-consumer

go 1.21

require github.com/seleniumhq/selenium-aether-go v0.0.0

// The consumer resolves the binding from the PACKAGED module copy staged under
// target/go-pkg (which carries the bundled native/ .so but has NO core/ sibling),
// so only the module's own bundled .so can satisfy cgo's rpath. The .example.ae
// harness rewrites this replace path to the staged copy at run time.
replace github.com/seleniumhq/selenium-aether-go => ../go-pkg
