#!/bin/sh

wlg_config=content/quickstarts/stress/stress-pod.yaml
k8s_config=${KUBECONFIG:-$HOME/.kube/config}
http_stress_ns=http-stress

### Functions ##################################################################
fail() {
  echo $@ >&2
}

warn() {
  fail "$ProgramName: $@"
}

die() {
  local err=$1
  shift
  fail "$ProgramName: $@"
  exit $err
}

check_admin() {
  local oc_whoami=`oc whoami`
  local oc_admin_user=system:admin

  test "$oc_whoami" = "$oc_admin_user"
}

oc_create_env() {
  oc create -f- <<_ENV_EOF_
apiVersion: v1
kind: ConfigMap
metadata:
  name: wlg-env
  namespace: $http_stress_ns
data:
  # which app to execute inside WLG pod
  RUN: "${RUN:-mb}"
  # benchmark run-time in seconds
  LOAD_GENERATORS: "${HTTP_TEST_LOAD_GENERATORS:-1}"
  # benchmark run-time in seconds
  RUN_TIME: "${HTTP_TEST_RUNTIME:-120}"
  # maximum delay between client requests in ms
  MB_DELAY: "${MB_DELAY:-0}"
  # extended RE (egrep) to filter target routes
  MB_TARGETS: "${MB_TARGETS:-.}"
  # how many connections per target route
  MB_CONNS_PER_TARGET: "${MB_CONNS_PER_TARGET:-1}"
  # HTTP method (GET by default)
  MB_METHOD: "${HTTP_TEST_MB_METHOD:-GET}"
  # body length of POST requests in characters
  MB_REQUEST_BODY_SIZE: "${HTTP_TEST_MB_REQUEST_BODY_SIZE:-1024}"
  # how many HTTP keep-alive requests to send before sending "Connection: close".
  MB_KA_REQUESTS: "${MB_KA_REQUESTS:-1}"
  # use TLS session reuse [yn]
  MB_TLS_SESSION_REUSE: "${HTTP_TEST_MB_TLS_SESSION_REUSE:-true}"
  # thread ramp-up time in seconds
  MB_RAMP_UP: "${HTTP_TEST_MB_RAMP_UP:-0}"
  # target path for HTTP(S) requests
  URL_PATH: "${URL_PATH:-/}"
  # Endpoint for collecting results from workload generator node(s).  Keep empty if copying is not required.
  # - scp://[user@]server:[path]
  # - kcp://[namespace/]pod:[path]
  SERVER_RESULTS: "${HTTP_TEST_SERVER_RESULTS}"
  # the kubeconfig file to use when talking to the cluster
  KUBECONFIG: "/etc/kubernetes/k8s.conf"
_ENV_EOF_
}

oc_create() {
  local wlg=1

  oc new-project $http_stress_ns --skip-config-write
  oc_create_env || \
    die 1 "Cannot create environment ConfigMap for WLG pod(s)."
  oc get cm wlg-env --template '{{printf "%s\n" .data}}' -n=$http_stress_ns	# Print some debugging information for the WLG pod
  oc create cm wlg-targets --from-file=wlg-targets=./routes.txt -n=$http_stress_ns || \
    die 1 "Cannot create wlg-targets ConfigMap for WLG pod(s)."
  oc create secret generic wlg-ssh-key --from-file=wlg-ssh-key=$HTTP_TEST_SERVER_RESULTS_SSH_KEY -n=$http_stress_ns || \
    die 1 "Cannot create wlg-ssh-key Secret for WLG pod(s)."
  oc create cm k8s-config --from-file=k8s-config=$k8s_config -n=$http_stress_ns || \
    die 1 "Cannot create k8s-config ConfigMap for WLG pod(s)."

  test "$HTTP_TEST_LOAD_GENERATOR_NODES" && check_admin && {
    # Load generator nodes were specified and we have a cluster admin, steer the workload generator
    NODE_SELECTOR='{"test": "wlg"}'
  }

  # create all the workload generators
  while test $wlg -le ${HTTP_TEST_LOAD_GENERATORS:-1}
  do
    oc process \
      -pIDENTIFIER=$wlg \
      -pHTTP_TEST_STRESS_CONTAINER_IMAGE="${HTTP_TEST_STRESS_CONTAINER_IMAGE}" \
      -pNODE_SELECTOR="${NODE_SELECTOR:-null}" \
      -f $wlg_config \
      -n=$http_stress_ns | \
        oc create -f- -n=$http_stress_ns &
    sleep 0.1s
    wlg=$(($wlg + 1))
  done
}

oc_cleanup() {
  exec 3>&1 4>&2 >/dev/null 2>&1
  oc delete pods -n=$http_stress_ns --all
  oc delete cm -n=$http_stress_ns --all      # wlg-targets! (e.g. switch from http->edge)
  oc delete secret wlg-ssh-key -n=$http_stress_ns || true
  oc delete ns $http_stress_ns || true
  exec 2>&4 1>&3
}

client_wait_complete() {
  local completed
  while true; do
    completed=$(oc get pods --no-headers -n=$http_stress_ns -l=app=http-stress --field-selector=status.phase=Succeeded 2>/dev/null | wc -l)
    echo "Completed wlg pods: $completed/${HTTP_TEST_LOAD_GENERATORS}"
    test $completed -eq ${HTTP_TEST_LOAD_GENERATORS} && break
    sleep 10
  done
}

oc_cleanup
oc_create
client_wait_complete
oc_cleanup
