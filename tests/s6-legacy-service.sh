#!/usr/bin/env bash
# Proves templates/usr/local/bin/s6-legacy-service in the workspace base image, with s6-overlay as
# PID 1: a service the ansible-setup oneshot writes to /etc/services.d starts on the same boot,
# and after boot the helper adds a new service and restarts a changed one.
# Needs Docker. Leaves nothing behind: the image and container are removed on exit.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
base=${BASE_IMAGE:-ghcr.io/wyrd-company/devcontainers/base:resolute}
tag=s6-legacy-service-test:$$
name=s6-legacy-service-test-$$
ctx=$(mktemp -d)
[ -n "${KEEP:-}" ] || trap 'docker rm -f "$name" >/dev/null 2>&1 || true; docker rmi -f "$tag" >/dev/null 2>&1 || true; rm -rf "$ctx"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

cp "$root/templates/usr/local/bin/s6-legacy-service" "$ctx/"
# Stands in for the playbook at startup: installs a service, then calls the helper, as container.yml does
cat > "$ctx/ansible-setup" <<'SH'
#!/bin/sh
mkdir -p /etc/services.d/probe
printf '#!/bin/sh\nexec sleep infinity\n' > /etc/services.d/probe/run
chmod +x /etc/services.d/probe/run
/usr/local/bin/s6-legacy-service probe > /run/startup-output
SH
chmod +x "$ctx/ansible-setup"
cat > "$ctx/Dockerfile" <<DOCKER
FROM $base
COPY s6-legacy-service ansible-setup /usr/local/bin/
RUN mkdir -p /etc/s6-overlay/s6-rc.d/ansible-setup/dependencies.d /etc/s6-overlay/user-bundles.d/user/contents.d \
 && echo oneshot > /etc/s6-overlay/s6-rc.d/ansible-setup/type \
 && echo /usr/local/bin/ansible-setup > /etc/s6-overlay/s6-rc.d/ansible-setup/up \
 && touch /etc/s6-overlay/s6-rc.d/ansible-setup/dependencies.d/base /etc/s6-overlay/user-bundles.d/user/contents.d/ansible-setup
DOCKER
docker build -q -t "$tag" "$ctx" >/dev/null
docker run -d --name "$name" "$tag" sleep infinity >/dev/null
dx() { docker exec "$name" "$@"; }
up() { dx /command/s6-svstat -o up "/run/service/$1" 2>/dev/null | grep -qx true; }
wait_up() { for _ in $(seq 50); do up "$1" && return 0; sleep 0.2; done; return 1; }

wait_up probe || fail "probe, written during ansible-setup, did not start on the same boot"
[ -z "$(dx cat /run/startup-output)" ] || fail "the helper acted at startup: $(dx cat /run/startup-output)"
echo "ok: a service written during ansible-setup starts on the same boot"

dx sh -c 'mkdir -p /etc/services.d/probe2 && printf "#!/bin/sh\nexec sleep infinity\n" > /etc/services.d/probe2/run && chmod +x /etc/services.d/probe2/run'
[ "$(dx s6-legacy-service probe2)" = added ] || fail "probe2 was not added"
wait_up probe2 || fail "probe2 did not start after it was added"
[ -z "$(dx s6-legacy-service probe2)" ] || fail "an unchanged, supervised service was touched"
echo "ok: after boot, a new service is added and started"

before=$(dx /command/s6-svstat -o pid /run/service/probe2)
dx sh -c 'printf "#!/bin/sh\nexec sleep 99999\n" > /etc/services.d/probe2/run'
[ "$(dx s6-legacy-service probe2 restart)" = restarted ] || fail "probe2 was not restarted"
for _ in $(seq 50); do
  after=$(dx /command/s6-svstat -o pid /run/service/probe2)
  [ "$after" != "$before" ] && [ "$after" != -1 ] && break; sleep 0.2
done
[ "$after" != "$before" ] || fail "probe2 kept pid $before"
dx ps -o args= -p "$after" | grep -qx 'sleep 99999' || fail "probe2 does not run its new run file"
echo "ok: a changed service is restarted with its new run file"
echo PASS
