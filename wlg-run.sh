#!/bin/sh

wlg_config=content/quickstarts/stress/stress-pod.yaml
k8s_config=${KUBECONFIG:-$HOME/.kube/config}
centos_stress_ns=centos-stress

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
  namespace: $centos_stress_ns
data:
  # which app to execute inside WLG pod
  RUN: "${RUN:-mb}"
  # benchmark run-time in seconds
  LOAD_GENERATORS: "${LOAD_GENERATORS:-1}"
  # benchmark run-time in seconds
  RUN_TIME: "${RUN_TIME:-120}"
  # maximum delay between client requests in ms
  MB_DELAY: "${MB_DELAY:-0}"
  # extended RE (egrep) to filter target routes
  MB_TARGETS: "${MB_TARGETS:-.}"
  # how many connections per target route
  MB_CONNS_PER_TARGET: "${MB_CONNS_PER_TARGET:-1}"
  # HTTP method (GET by default)
  MB_METHOD: "${MB_METHOD:-GET}"
  # body length of POST requests in characters
  MB_REQUEST_BODY_SIZE: "${MB_REQUEST_BODY_SIZE:-1024}"
  # how many HTTP keep-alive requests to send before sending "Connection: close".
  MB_KA_REQUESTS: "${MB_KA_REQUESTS:-1}"
  # use TLS session reuse [yn]
  MB_TLS_SESSION_REUSE: "${MB_TLS_SESSION_REUSE:-true}"
  # thread ramp-up time in seconds
  MB_RAMP_UP: "${MB_RAMP_UP:-0}"
  # target path for HTTP(S) requests
  URL_PATH: "${URL_PATH:-/}"
  # Endpoint for collecting results from workload generator node(s).  Keep empty if copying is not required.
  # - scp://[user@]server:[path]
  # - kcp://[namespace/]pod:[path]
  SERVER_RESULTS: "${SERVER_RESULTS}"
  # the kubeconfig file to use when talking to the cluster
  KUBECONFIG: "/etc/kubernetes/k8s.conf"
_ENV_EOF_
}

oc_create() {
  local wlg=1
  local skip_config_write

  test $(oc project -q 2>/dev/null | wc -l) -eq 1 && skip_config_write=--skip-config-write	# don't switch to the new project if we have access to the current project
  oc new-project $centos_stress_ns $skip_config_write						# don't use "oc create ns", issues when working as non-privileged user
  oc_create_env || \
    die 1 "Cannot create environment ConfigMap for WLG pod(s)."
  oc create cm wlg-targets --from-file=wlg-targets=./routes.txt -n=$centos_stress_ns || \
    die 1 "Cannot create wlg-targets ConfigMap for WLG pod(s)."
  oc create secret generic wlg-ssh-key --from-file=wlg-ssh-key=$SERVER_RESULTS_SSH_KEY -n=$centos_stress_ns || \
    die 1 "Cannot create wlg-ssh-key Secret for WLG pod(s)."
  oc create cm k8s-config --from-file=k8s-config=$k8s_config -n=$centos_stress_ns || \
    die 1 "Cannot create k8s-config ConfigMap for WLG pod(s)."

  check_admin && {
    NODE_SELECTOR='{"test": "wlg"}'
  }

  # create all the workload generators
  while test $wlg -le ${LOAD_GENERATORS:-1}
  do
    oc process \
      -pIDENTIFIER=$wlg \
      -pNODE_SELECTOR="${NODE_SELECTOR:-null}" \
      -f $wlg_config \
      -n=$centos_stress_ns | \
        oc create -f- -n=$centos_stress_ns &
    sleep 0.1s
    wlg=$(($wlg + 1))
  done
}

oc_cleanup() {
  exec 3>&1 4>&2 >/dev/null 2>&1
  oc delete pods -n=$centos_stress_ns --all
  oc delete cm -n=$centos_stress_ns --all      # wlg-targets! (e.g. switch from http->edge)
  oc delete secret wlg-ssh-key -n=$centos_stress_ns || true
  oc delete ns $centos_stress_ns || true
  exec 2>&4 1>&3
}

client_wait_complete() {
  local completed
  while true; do
    completed=$(oc get pods --no-headers -n=$centos_stress_ns -l=app=centos-stress --field-selector=status.phase=Succeeded 2>/dev/null | wc -l)
    echo "Completed wlg pods: $completed/${LOAD_GENERATORS}"
    test $completed -eq ${LOAD_GENERATORS} && break
    sleep 10
  done
}

oc_cleanup
oc_create
client_wait_complete
oc_cleanup
