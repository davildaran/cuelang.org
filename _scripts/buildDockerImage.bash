#!/usr/bin/env bash

set -euxo pipefail

# cd to the parent directory to that containing the script
cd "$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )/.."


cd internal/cmd/preprocessor/cmd
tag="preprocessor:$(cat _docker/Dockerfile _docker/entrypoint.sh | sha256sum | awk '{print $1}')"
cat <<EOD > gen_dockerimagetag.go
package cmd

const dockerImageTag = "$tag"
EOD

caching=""
if [ "${CI:-}" == "true" ]
then
	caching="--cache-from=type=local,src=$HOME/.cache/dockercache --cache-to=type=local,dest=$HOME/.cache/dockercache"
fi

# TODO: pass in host UID and GID and Go cache paths to avoid using a buildkit
# caching layer.  This is particularly important in CI.
docker buildx build $caching -t $tag --load -f ./_docker/Dockerfile ./_docker