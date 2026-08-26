.PHONY: all .tests.ae
all: .tests.ae
.tests.ae:
	@_s=$$(date +%s%3N 2>/dev/null); case "$$_s" in ''|*[!0-9]*) _s=$$(date +%s)000;; esac; '/home/paul/scm/selenium/rb/target/_ae_build_all' '/home/paul/scm/selenium/rb' 'tests:.' > '/home/paul/scm/selenium/rb/target/.aeb/logs/tests_..log' 2>&1; _r=$$?; _e=$$(date +%s%3N 2>/dev/null); case "$$_e" in ''|*[!0-9]*) _e=$$(date +%s)000;; esac; echo $$_r > '/home/paul/scm/selenium/rb/target/.aeb/rc/.tests.ae.rc'; echo $$((_e-_s)) > '/home/paul/scm/selenium/rb/target/.aeb/rc/.tests.ae.ms'; exit $$_r
