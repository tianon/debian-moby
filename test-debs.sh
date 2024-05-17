#!/usr/bin/env bash
set -Eeuo pipefail

dist="$1"; shift

debs="$1"; shift
[ -d "$debs" ]
debs="$(readlink -ve "$debs")"

img="debian:$dist"
if ! docker image inspect --format '.' "$img" &> /dev/null; then
	docker pull "$img"
fi

args=(
	--interactive
	--rm
	--init
	--name "test-moby-debs-$dist"
	--mount "type=bind,src=$debs,dst=/debs,ro"
	--privileged
	--volume /var/lib/containerd
	--volume /var/lib/docker
	--tmpfs /run
)

if [ -t 0 ] && [ -t 1 ]; then
	args+=( --tty )
fi

script="$(
cat <<-'EOBASH'
	# https://github.com/moby/moby/blob/38805f20f9bcc5e87869d6c79d432b166e1c88b4/hack/dind#L28-L38
	if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
		mkdir -p /sys/fs/cgroup/init
		xargs -rn1 < /sys/fs/cgroup/cgroup.procs > /sys/fs/cgroup/init/cgroup.procs || :
		sed -e 's/ / +/g' -e 's/^/+/' < /sys/fs/cgroup/cgroup.controllers > /sys/fs/cgroup/cgroup.subtree_control
	fi

	apt-get update -qq
	arch="$(dpkg --print-architecture)"
	apt-get install -yqq --no-install-recommends -V ca-certificates iptables /debs/moby-*_"${arch}".deb

	containerd --version
	ctr --version
	docker --version
	docker buildx version
	runc --version

	containerd &
	timeout 10s sh -c "while ! ctr version; do sleep 1; done"

	ctr image pull docker.io/library/hello-world:latest
	ctr run --rm docker.io/library/hello-world:latest hello

	dockerd &
	timeout 10s sh -c "while ! docker version; do sleep 1; done"

	docker run --rm hello-world
	docker run --rm --init hello-world

	printf 'FROM hello-world\nRUN ["/hello"]' | DOCKER_BUILDKIT=0 docker build --tag hello-build:classic -

	printf 'FROM hello-world\nRUN ["/hello"]' | docker buildx build --tag hello-build:buildkit -

	docker buildx create --name tianon --node tianon --driver docker-container --driver-opt image=tianon/buildkit --bootstrap
	printf 'FROM hello-world\nRUN ["/hello"]' | docker buildx build --builder tianon --tag hello-build:buildx -

	docker image inspect --format '.' hello-build:classic hello-build:buildkit hello-build:buildx > /dev/null

	docker images
EOBASH
)"

exec docker run "${args[@]}" "$img" bash -Eeuo pipefail -xc "$script"
