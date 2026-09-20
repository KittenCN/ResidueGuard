// Sanitized macOS 27 build 26A428 disposable-VM captures; no live-host fixtures.
let runtimeFixtureRunning = #"""
gui/501/example.residueguard.fixture.iso01 = {
	active count = 1
	path = /Users/fixture-user/Library/LaunchAgents/example.residueguard.fixture.iso01.plist
	type = LaunchAgent
	state = running

	program = /Users/fixture-user/Library/ResidueGuard-VM-ISO01/fixture
	arguments = {
		/Users/fixture-user/Library/ResidueGuard-VM-ISO01/fixture
	}

	inherited environment = {
		SSH_AUTH_SOCK => /var/run/com.apple.launchd.FIXTURE/Listeners
	}

	default environment = {
		PATH => /usr/bin:/bin:/usr/sbin:/sbin
	}

	environment = {
		OSLogRateLimit => 64
		XPC_SERVICE_NAME => example.residueguard.fixture.iso01
	}

	domain = gui/501 [100002]
	asid = 100002
	minimum runtime = 10
	exit timeout = 5
	runs = 1
	pid = 1038
	immediate reason = non-ipc demand
	forks = 0
	execs = 1
	initialized = 1
	trampolined = 1
	started suspended = 0
	proxy started suspended = 0
	checked allocations = 0 (queried = 1)
	checked allocations reason = no host
	checked allocations flags = 0x0
	last exit code = (never exited)

	resource coalition = {
		ID = 1072
		type = resource
		state = active
		active count = 1
		name = example.residueguard.fixture.iso01
	}

	jetsam coalition = {
		ID = 1073
		type = jetsam
		state = active
		active count = 1
		name = example.residueguard.fixture.iso01
	}

	spawn type = daemon (3)
	jetsam priority = 40
	jetsam memory limit (active) = (unlimited)
	jetsam memory limit (inactive) = (unlimited)
	jetsamproperties category = daemon
	jetsam thread limit = 32
	cpumon = default
	sanitizer flags = 0x0

	properties = inferred program
}
"""#
let runtimeFixtureRegistered = #"""
gui/501/example.residueguard.fixture.iso01 = {
	active count = 0
	path = /Users/fixture-user/Library/LaunchAgents/example.residueguard.fixture.iso01.plist
	type = LaunchAgent
	state = not running

	program = /Users/fixture-user/Library/ResidueGuard-VM-ISO01/fixture
	arguments = {
		/Users/fixture-user/Library/ResidueGuard-VM-ISO01/fixture
	}

	inherited environment = {
		SSH_AUTH_SOCK => /var/run/com.apple.launchd.FIXTURE/Listeners
	}

	default environment = {
		PATH => /usr/bin:/bin:/usr/sbin:/sbin
	}

	environment = {
		OSLogRateLimit => 64
		XPC_SERVICE_NAME => example.residueguard.fixture.iso01
	}

	domain = gui/501 [100002]
	asid = 100002
	minimum runtime = 10
	exit timeout = 5
	runs = 0
	last exit code = (never exited)

	spawn type = daemon (3)
	jetsam priority = 40
	jetsam memory limit (active) = (unlimited)
	jetsam memory limit (inactive) = (unlimited)
	jetsamproperties category = daemon
	jetsam thread limit = 32
	cpumon = default
	sanitizer flags = 0x0

	properties = inferred program
}
"""#
let runtimeFixtureBaseline = #"""
Bad request.
Could not find service "example.residueguard.fixture.iso01" in domain for user gui: 501
"""#
let runtimeFixtureAfterBootout = #"""
Bad request.
Could not find service "example.residueguard.fixture.iso01" in domain for user gui: 501
"""#
let runtimeFixtureAfterRestore = #"""
Bad request.
Could not find service "example.residueguard.fixture.iso01" in domain for user gui: 501
"""#

// Same verified VM build after guest reboot/login; restored plist re-registered.
let runtimeFixtureAfterReboot = #"""
gui/501/example.residueguard.fixture.iso01 = {
	active count = 0
	path = /Users/fixture-user/Library/LaunchAgents/example.residueguard.fixture.iso01.plist
	type = LaunchAgent
	state = not running

	program = /Users/fixture-user/Library/ResidueGuard-VM-ISO01/fixture
	arguments = {
		/Users/fixture-user/Library/ResidueGuard-VM-ISO01/fixture
	}

	inherited environment = {
		SSH_AUTH_SOCK => /var/run/com.apple.launchd.FIXTURE/Listeners
	}

	default environment = {
		PATH => /usr/bin:/bin:/usr/sbin:/sbin
	}

	environment = {
		OSLogRateLimit => 64
		XPC_SERVICE_NAME => example.residueguard.fixture.iso01
	}

	domain = gui/501 [100002]
	asid = 100002
	minimum runtime = 10
	exit timeout = 5
	runs = 0
	last exit code = (never exited)

	spawn type = daemon (3)
	jetsam priority = 40
	jetsam memory limit (active) = (unlimited)
	jetsam memory limit (inactive) = (unlimited)
	jetsamproperties category = daemon
	jetsam thread limit = 32
	cpumon = default
	job state = uninitialized
	sanitizer flags = 0x0

	properties = inferred program | needs LWCR update | managed LWCR
}
"""#
