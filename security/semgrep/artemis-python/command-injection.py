# Test fixture for command-injection.yaml — run with `semgrep --test`, gated by selftest.
# Deliberately vulnerable scanner test data: never execute or copy into a project.
# `ruleid:` = a finding is expected on the next line; `ok:` = none is.

import subprocess
import sys

user_input = sys.argv[1]

# ruleid: artemis-py-subprocess-shell-true
subprocess.run(user_input, shell=True)
# ruleid: artemis-py-subprocess-shell-true
subprocess.call(user_input, shell=True)
# ruleid: artemis-py-subprocess-shell-true
subprocess.Popen(user_input, shell=True)
# ruleid: artemis-py-subprocess-shell-true
subprocess.check_output(user_input, shell=True)
# ruleid: artemis-py-subprocess-shell-true
subprocess.check_call(user_input, shell=True)

# Interpolating into the command is the actual injection, and must stay caught.
# ruleid: artemis-py-subprocess-shell-true
subprocess.run(f"ls {user_input}", shell=True)

# A hardcoded command has no injection surface. Flagging these was the false-positive
# class that trains people to ignore the rule.
# ok: artemis-py-subprocess-shell-true
subprocess.run("ls -la", shell=True)
# ok: artemis-py-subprocess-shell-true
subprocess.check_output("git rev-parse HEAD", shell=True)

# shell=False (the default) is the safe form and must never be flagged.
# ok: artemis-py-subprocess-shell-true
subprocess.run(["ls", "-la", user_input])

# ruleid: artemis-py-eval-exec-nonliteral
eval(user_input)
# ruleid: artemis-py-eval-exec-nonliteral
exec(user_input)
# ok: artemis-py-eval-exec-nonliteral
eval("1 + 1")
