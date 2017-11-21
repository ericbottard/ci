#!/bin/bash
set -exuo pipefail

echo "System Tests for sk8s"

build_root=$(pwd)

source "$build_root/git-pfs-ci/tasks/scripts/common.sh"
init_docker
init_kubeconfig

SK8S_VERSION=$(determine_sk8s_version "$build_root/git-sk8s" "$build_root/sk8s-version")
existing_sk8s_ns=$(find_existing_sk8s_ns "$SK8S_VERSION")

http_gw_host=$(kubectl -n "$existing_sk8s_ns" get svc -l component=http-gateway -o jsonpath='{.items[0].status.loadBalancer.ingress[].ip}')
http_gw_port=$(kubectl -n "$existing_sk8s_ns" get svc -l component=http-gateway -o jsonpath='{.items[0].spec.ports[?(@.name == "http")].port}')

kafka_pod=$(kubectl -n "$existing_sk8s_ns"  get pod -l component=kafka-broker -o jsonpath='{.items[0].metadata.name}')

# init test env vars

export SYS_TEST_JAVA_INVOKER_VERSION="$SK8S_VERSION"
export SYS_TEST_NS="$existing_sk8s_ns"
export SYS_TEST_HTTP_GW_URL="http://${http_gw_host}:${http_gw_port}"
export SYS_TEST_KAFKA_POD_NAME="$kafka_pod"
export SYS_TEST_DOCKER_ORG="$DOCKER_ORG"
export SYS_TEST_DOCKER_USERNAME="$DOCKER_USERNAME"
export SYS_TEST_DOCKER_PASSWORD="$DOCKER_PASSWORD"
export SYS_TEST_BASE_DIR="$build_root/git-sk8s"
export SYS_TEST_MSG_RT_TIMEOUT_SEC=60

export GOPATH=$(go env GOPATH)
workdir=$GOPATH/src/github.com/pivotal-cf
mkdir -p $workdir
cp -rf git-pfs-system-test $workdir/pfs-system-test
cd $workdir/pfs-system-test
dep ensure

set +e
./test.sh
set -e

test_retcode="$?"
if [ "0" != "$test_retcode" ]; then
  echo "Tests Failed. Printing logs from all pods in [$existing_sk8s_ns]"

  kubectl get pods -n "$existing_sk8s_ns" -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | xargs -I{} kubectl logs {} -n "$existing_sk8s_ns"
fi

exit $test_retcode