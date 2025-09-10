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
	apt-get install -yqq --no-install-recommends -V ca-certificates iptables git /debs/moby-*_"${arch}".deb

	containerd --version
	ctr --version
	docker --version
	docker buildx version
	runc --version

	containerd & pid="$!"
	timeout 10s sh -c "while ! ctr version; do sleep 1; done"

	if ctr plugins ls | grep opt; then
		exit 1
	fi

	ctr image pull docker.io/library/hello-world:latest
	ctr run --rm docker.io/library/hello-world:latest hello

	busybox='docker.io/library/busybox@sha256:5eef5ed34e1e1ff0a4ae850395cbf665c4de6b4b83a32a0bc7bcb998e24e7bbb' # "latest" as of 2024-05-25
	ctr image pull "$busybox"
	out="$(ctr run --rm --user 1000:1000 "$busybox" bb id)"
	[ "$out" = 'uid=1000 gid=1000 groups=1000' ]

	# stop "containerd" so dockerd can start it up and we can test the "dockerd starts/manages containerd" behavior
	kill "$pid"
	wait "$pid"
	# TODO also clear out containerd state?

	dockerd &
	timeout 10s sh -c "while ! docker version; do sleep 1; done"

	if ctr -a /run/docker/containerd/containerd.sock plugins ls | grep opt; then
		exit 1
	fi

	docker run --rm hello-world
	docker run --rm --init hello-world

	printf 'FROM hello-world\nRUN ["/hello"]' | DOCKER_BUILDKIT=0 docker build --tag hello-build:classic -

	DOCKER_BUILDKIT=0 docker build --tag hello-build:classic-git 'https://github.com/docker-library/hello-world.git#3fb6ebca4163bf5b9cc496ac3e8f11cb1e754aee:amd64/hello-world'

	printf 'FROM hello-world\nRUN ["/hello"]' | docker buildx build --tag hello-build:buildkit -

	docker buildx create --name tianon --node tianon --driver docker-container --driver-opt image=tianon/buildkit --bootstrap
	printf 'FROM hello-world\nRUN ["/hello"]' | docker buildx build --builder tianon --tag hello-build:buildx -

	docker buildx build --tag hello-build:buildx-git 'https://github.com/docker-library/hello-world.git#3fb6ebca4163bf5b9cc496ac3e8f11cb1e754aee:amd64/hello-world'

	docker image inspect --format '.' \
		hello-build:classic \
		hello-build:classic-git \
		hello-build:buildkit \
		hello-build:buildx \
		hello-build:buildx-git \
		> /dev/null

	docker images

	nofile="$(docker run --rm busybox sh -c 'ulimit -n')"
	test "$nofile" = "$(( 1024 * 1024 ))"
EOBASH
)"

exec docker run "${args[@]}" "$img" bash -Eeuo pipefail -xc "$script"
