#!/usr/bin/env bash
# =============================================================================
# bash-3.test.sh — Tests for bash_check_remote_readonly (rule bash-3)
# =============================================================================
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RULES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.claude/hooks/rules" && pwd)"

# Source assert harness FIRST (installs mocks before rule is loaded)
source "$TESTS_DIR/lib/assert.sh"

# Set required globals
PROJECT_DIR="/home/testuser/myproject"
CWD="/home/testuser/myproject"
HOME="/home/testuser"

# Source the rule under test
source "$RULES_DIR/bash-3-remote-readonly.sh"

# =============================================================================

echo "bash-3: Remote Readonly"

suite "kubectl — blocked"

bash_check_remote_readonly "kubectl apply -f manifest.yaml"
assert_blocked "kubectl apply -f manifest.yaml" "bash-3"

bash_check_remote_readonly "kubectl delete pod mypod"
assert_blocked "kubectl delete pod mypod" "bash-3"

bash_check_remote_readonly "kubectl exec -it pod -- bash"
assert_blocked "kubectl exec -it pod -- bash" "bash-3"

suite "kubectl — allowed"

bash_check_remote_readonly "kubectl get pods"
assert_allowed "kubectl get pods"

bash_check_remote_readonly "kubectl describe deployment app"
assert_allowed "kubectl describe deployment app"

bash_check_remote_readonly "kubectl logs mypod"
assert_allowed "kubectl logs mypod"

bash_check_remote_readonly "kubectl top nodes"
assert_allowed "kubectl top nodes"

suite "ssh — blocked"

bash_check_remote_readonly "ssh host rm -rf /data"
assert_blocked "ssh host rm -rf /data" "bash-3"

bash_check_remote_readonly "ssh host systemctl restart nginx"
assert_blocked "ssh host systemctl restart nginx" "bash-3"

bash_check_remote_readonly "ssh host apt install curl"
assert_blocked "ssh host apt install curl" "bash-3"

# Regression: apt-get was previously corrupted to apt-et by the boolean-flag sed
bash_check_remote_readonly "ssh host apt-get install curl"
assert_blocked "ssh host apt-get install curl (regression: -g in apt-get)" "bash-3"

bash_check_remote_readonly "ssh -v host apt-get install curl"
assert_blocked "ssh -v host apt-get install curl (regression: flag before host)" "bash-3"

suite "ssh — allowed"

bash_check_remote_readonly "ssh host"
assert_allowed "ssh host (interactive, no remote cmd)"

bash_check_remote_readonly "ssh host ls /var/log"
assert_allowed "ssh host ls /var/log"

bash_check_remote_readonly "ssh host cat /etc/hosts"
assert_allowed "ssh host cat /etc/hosts"

bash_check_remote_readonly "ssh -i ~/.ssh/id_rsa host grep error /var/log/app.log"
assert_allowed "ssh -i ~/.ssh/id_rsa host grep error /var/log/app.log"

# Regression: grep -v in the remote command must not be stripped as an SSH flag
bash_check_remote_readonly "ssh host grep -v error /var/log/app.log"
assert_allowed "ssh host grep -v (remote flag must not be stripped as SSH flag)"

summary
