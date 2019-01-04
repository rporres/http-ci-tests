#!/bin/bash

ProgramName=${0##*/}

. ./env.sh

### Global variables ###########################################################
param_name=()			# parameters, name
param_fn=()			# parameters, function name
param_hlp=()			# parameters, help
http_ns_label=test=http		# label for namespaces holding application pods
http_pod_label=$http_ns_label	# label for application pods
http_server=nginx		# backend server for http tests (h2o|nginx)
declare -a a_region		# array of old node region labels

# pbench-specific variables ####################################################
pbench_use=true
pbench_dir=/var/lib/pbench-agent	# pbench-agent directory
pbench_prefix=pbench-user-benchmark_
#pbench_containerized=y			# is pbench running containerized?
pbench_mb_wrapper=./pbench-mb-wrapper.sh
file_total_rps=rps.txt
file_total_latency=latency_95.txt
file_quit=quit				# if this file is detected during test runs, abort

# Golang cluster loader binary #################################################
export EXTENDED_TEST_BIN=/usr/libexec/atomic-openshift/extended.test	# atomic-openshift-tests package

# mb-specific variables ########################################################
routes_file=routes.txt		# a file with routes to pass to cluster loader
WLG_IMAGE=docker.io/jmencak/centos-stress	# workload generator image
: ${RUN_TIME:=120}		# benchmark run-time in seconds
: ${MB_TLS_SESSION_REUSE:=true}	# use TLS session reuse [yn]
: ${MB_METHOD:=GET}		# HTTP method to use for backend servers (GET/POST)
: ${MB_RESPONSE_SIZE:=1024}	# backend server (200 OK) response document length
: ${MB_REQUEST_BODY_SIZE:=1024}	# body length of POST requests in characters for backend servers

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

usage() {
  local err="$1"
  local key hlp
  local i=0

  cat <<_HLP1_ 1>&2
Usage: $ProgramName [options] [tasks]

Options:
  --help, -h        this help

Tasks:
 all: Run all tasks involved in setting up the environment and running the tests.
_HLP1_

  for key in "${param_name[@]}" ; do
    hlp="${param_hlp[$i]}"
    ((i++))
    cat <<_HLP2_ 1>&2
 $key: $hlp
_HLP2_
  done

  test "$err" && exit $err
}

param_set() {
  local param fn hlp
  local i=0
  local old_ifs="$IFS"
  IFS='|'
  while read -r param fn hlp ; do
    test ${param:0:1} = "#" && continue
    param_name[$i]="$param"
    param_fn[$i]="$fn"
    param_hlp[$i]="$hlp"
    ((i++))
  done << _PARAM_
environment-dump|environment_dump|Dump the environment for the purposes of re-running some of the test iterations manually.
router_liveness_probe-disable|router_liveness_probe|Increase period seconds for the router liveness probe.
load_generator-label|load_generator_nodes_label|Label and taint the node(s) for the load generator pod(s).
load_generator-portrange|load_generator_nodes_local_port_range|Increase local port range on the load generator node(s).
pbench-register|pbench_ansible|Register pbench on the OpenShift cluster using pbench-ansible.
pbench-server-cfg|pbench_server_cfg|Set pbench_results_redirector and pbench_web_server to PBENCH_SERVER if set.
pbench-clear-results|pbench_clear_results|Clear results from previous pbench runs.
cluster-load|cl_load|Populate the cluster with application pods and routes.
benchmark-run|benchmark_run|Run the HTTP(s) benchmark against routes in '$routes_file'.
process-results|process_results|Process results collected in the benchmark run.
results-move|pbench_move_results|Move the benchmark results to a pbench server
load_generator-unlabel|load_generator_nodes_unlabel|Unlabel and remove taints on the node(s) for the load generator pod(s).
namespace-cleanup|namespace_cleanup|Delete all namespaces with application pods, services and routes created for the purposes of HTTP tests.
_PARAM_
  IFS="$old_ifs"
}

param2fn() {
  local param="$1"
  local key fn
  local i=0

  for key in "${param_name[@]}" ; do
    if test "$key" = "$param" ; then
      fn="${param_fn[$i]}"
      echo "$fn"
      return 0
    fi
    ((i++))
  done

  return 1
}

environment_dump() {
  cat >env-dump.sh<<EOF
# Test configuration: a label to append to pbench directories and mb result directories.
export TEST_CFG=${TEST_CFG:-1router}
# A list of paths to k8s configuration files.  Colon-delimited for Linux.
export KUBECONFIG=${KUBECONFIG:-/root/.kube/config}
# Setup pbench using "Pbench Ansible".
export SETUP_PBENCH=${SETUP_PBENCH:-true}
# Set pbench_results_redirector and pbench_web_server.
export PBENCH_SERVER=${PBENCH_SERVER:-pbench.perf.lab.eng.bos.redhat.com}
# Pbench scraper/wedge usage for r2r analysis.
export PBENCH_SCRAPER_USE=${PBENCH_SCRAPER_USE:-false}
# A path to the inventory to needed by "Pbench Ansible":
# https://github.com/distributed-system-analysis/pbench/tree/master/contrib/ansible/openshift
# and possibly generated by openshift_labeller:
# https://github.com/chaitanyaenr/openshift-labeler
export TOOLING_INVENTORY=${TOOLING_INVENTORY:-/root/tooling_inventory}
# Clear results from previous pbench runs.
export CLEAR_RESULTS=${CLEAR_RESULTS:-true}
# Move the benchmark results to a pbench server.
export MOVE_RESULTS=${MOVE_RESULTS:-false}
# When enabled, run containerized Pbench.
export CONTAINERIZED=${CONTAINERIZED:-false}
# HTTP-test specifics
# A synchronization endpoint listening at :9090 by default.
export GUN=${GUN:-b1.lan}
# username@server to scp results from workload generator node(s) to.
export SERVER_RESULTS=${SERVER_RESULTS:-root@$GUN}
# Load-generator nodes described by an extended regular expression (use "oc get nodes" node names).
export LOAD_GENERATOR_NODES=${LOAD_GENERATOR_NODES:-b[5-5].lan}
# Number of projects to create for each type of application (4 types currently).
export CL_PROJECTS=${CL_PROJECTS:-10}
# Number of templates to create per project.
export CL_TEMPLATES=${CL_TEMPLATES:-1}
# Run time of individual HTTP test iterations in seconds.
export RUN_TIME=${RUN_TIME:-120}
# Use TLS session reuse.
export MB_TLS_SESSION_REUSE=${MB_TLS_SESSION_REUSE:-true}
# HTTP method to use for backend servers (GET/POST).
export MB_METHOD=${MB_METHOD:-GET}
# Backend server (200 OK) response document length.
export MB_RESPONSE_SIZE=${MB_RESPONSE_SIZE:-1024}
# Body length of POST requests in characters for backend servers.
export MB_REQUEST_BODY_SIZE=${MB_REQUEST_BODY_SIZE:-1024}
# Perform the test for the following (comma-separated) route terminations: mix,http,edge,passthrough,reencrypt
export ROUTE_TERMINATION=${ROUTE_TERMINATION:-mix}
# Run only a single HTTP test to establish functionality.
export SMOKE_TEST=${SMOKE_TEST:-false}
# Delete all namespaces with application pods, services and routes created for the purposes of HTTP tests.
export NAMESPACE_CLEANUP=${NAMESPACE_CLEANUP:-true}
EOF
}

# Increase period seconds for the router liveness probe.
router_liveness_probe() {
  local deployment selector d probe_set

  # Increase period seconds for the router liveness probe.
  for deployment in dc deployment
  do
    for selector in router=router app=router
    do
      for d in $(oc get $deployment --selector=$selector --template='{{range .items}}{{.metadata.name}}|{{.metadata.namespace}}{{"\n"}}{{end }}' --all-namespaces)
      do
        set -- ${d//|/ }
        d_name=$1
        d_namespace=$2
        oc set probe $deployment/$d_name --liveness --period-seconds=$RUN_TIME -n $d_namespace
        # Alternatively, delete the router liveness probe.
        #oc set probe $deployment/$d_name --liveness --remove -n $d_namespace
        probe_set=true
      done
    done
  done

  test "$probe_set" || die 1 "Couldn't set router liveness probe."
}

load_generator_nodes_get() {
  oc get nodes --no-headers | awk '{print $1}' | grep -E "$LOAD_GENERATOR_NODES"
}

load_generator_nodes_label_taint() {
  local label="${1:-y}" # unlabel/remove taint if not 'y'
  local i node placement taint region region_old

  if test "$label" = y ; then
    placement=placement=test
    taint=placement=test:NoSchedule
  else
    placement=placement-
    taint=placement-
  fi

  i=0
  for node in $(load_generator_nodes_get) ; do
    if test "$label" = y ; then
      # save old region
      a_region[$i]=$(oc get node "$node" --template '{{printf "%s\n" .metadata.labels.region}}')
      region=region=primary
    else
      # get old region from "stored regions" array
      region=region=${a_region[$i]:-primary}
    fi
    oc label node $node $placement
    oc label node $node $region --overwrite
    oc adm taint nodes $node $taint
    ((i++))
  done
}

# Label and taint the node(s) for the load generator pod(s).
load_generator_nodes_label() {
  load_generator_nodes_label_taint y
}

# Unlabel and remove taints on the node(s) for the load generator pod(s).
load_generator_nodes_unlabel() {
  load_generator_nodes_label_taint n
}

# Increase local port range on the load generator node(s).
load_generator_nodes_local_port_range() {
  local node
  local sysctl_file=/etc/sysctl.d/50-mb-local_port_range.conf

  for node in $(load_generator_nodes_get) ; do
    ssh -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$node <<_SSH_BLOCK_
echo 'net.ipv4.ip_local_port_range = 1000 65535' > $sysctl_file
restorecon $sysctl_file
sysctl -p $sysctl_file
_SSH_BLOCK_
done
}

# Register pbench on the OpenShift cluster using pbench-ansible.
pbench_ansible() {
  local pbench_git=https://github.com/distributed-system-analysis/pbench.git

  pushd $(pwd)
  if test "${SETUP_PBENCH}" = "true" ; then
    test "${TOOLING_INVENTORY}" || die 1 "TOOLING_INVENTORY undefined."
    test -e "${TOOLING_INVENTORY}" || die 1 "TOOLING_INVENTORY '$TOOLING_INVENTORY' does not exits."
    cd /root
    rm -rf pbench
    git clone $pbench_git
    cd /root/pbench/contrib/ansible/openshift/
    pbench-clear-tools
    ansible-playbook -vv -i ${TOOLING_INVENTORY} pbench_register.yml
  fi
  popd
}

# Setup pbench servers in pbench.cfg file.
pbench_server_cfg() {
  local pbench_cfg=/opt/pbench-agent/config/pbench-agent.cfg
  local ssh_scp_opts='-o StrictHostKeyChecking=no -i /root/.ssh/id_rsa'

  if test "$PBENCH_SERVER" -a test "${SETUP_PBENCH}" = true ; then
    sed -E -i "s;^\s*#?\s*(pbench_results_redirector|pbench_web_server)\s*=.*;\1=$PBENCH_SERVER;" $pbench_cfg
    sed -E -i "s;^\s*#?\s*(ssh_opts|scp_opts)\s*=.*;\1=$ssh_scp_opts;" $pbench_cfg
  fi
}

# Clear results from previous pbench runs.
pbench_clear_results() {
  if test "${CLEAR_RESULTS}" = "true" ; then
    pbench-clear-results
  fi
}

cl_max_pods_not_running() {
  local max_not_running="${1:-20}"
  local not_running

  while true ; do
    not_running=$(oc get pods --selector $http_ns_label --all-namespaces --no-headers | grep -E -v '(Running|Completed|Unknown)' | wc -l)
    test "$not_running" -le "$max_not_running" && break
    echo "$not_running pods not running"
    sleep 1
  done
}

cl_new_project_or_reuse() {
  local project="$1"
  local res

  if oc project $project >/dev/null 2>&1 ; then
    # $project exists, recycle it
    for res in rc dc bc pod service route ; do
      oc delete $res --all -n $project 2>&1
    done
  else
    # $project doesn't exist
    oc new-project $project
  fi
  oc label ns $project $http_ns_label --overwrite	# label the namespace for a cleanup after all test iterations are done
}

# Populate the cluster with application pods and routes.
cl_load() {
  local server_quickstart_dir="content/quickstarts/$http_server"
  local templates="$server_quickstart_dir/server-http.json $server_quickstart_dir/server-tls-edge.json $server_quickstart_dir/server-tls-passthrough.json $server_quickstart_dir/server-tls-reencrypt.json"
  local projects=${CL_PROJECTS:-10}		# 10, 30, 60, 180
  local project_start=1
  local templates_total=${CL_TEMPLATES:-50}	# number of templates per project
  local templates_start=1			# do not change or read the code to make sure it does what you want

  local project project_basename template p p_f i i_f

  test "$SMOKE_TEST" = true && templates_total=1	# override the number of templates if this is just a smoke test

  for template in $templates ; do
    for p in $(seq $project_start $projects) ; do
      p_f=$(printf "%03d" $p)
      project_basename=${template##*/}
      project_basename=${project_basename%%.*}-
      project=${project_basename}$p_f
      if test "$templates_start" -eq 1 ; then
        cl_new_project_or_reuse $project
      fi
      i=$templates_start
      while test $i -le $templates_total
      do
        i_f=$(printf "%03d" $i)
        oc process -pIDENTIFIER=$i_f -f $template | oc create -f- -n $project
        i=$((i+1))

        cl_max_pods_not_running 20
      done
    done
  done
}

# TODO: for golang cluster loader
pbench_user_benchmark_containerized() {
  local benchmark_test_config="$1"
  local scale_testing_dir=/root/scale-testing
  local controller_run=$scale_testing_dir/run.sh
  local controller_vars=$scale_testing_dir/vars

  cat >$controller_vars<<_VARS_EOF_
KUBECONFIG=/root/.kube/config
#benchmark_type=nodeVertical
#benchmark_type=masterVertical
benchmark_type=http
#benchmark=pbench-user-benchmark -C "$benchmark_test_config" -- ./cluster-loader.py -vaf config/stress-mb.yaml
benchmark_test_config=$benchmark_test_config
benchmark=/root/benchmark.sh
#benchmark=pbench-user-benchmark -- sleep 20
pbench_server=pbench.perf.lab.eng.bos.redhat.com
#move_results=False
#clear_results=False
_VARS_EOF_

  $controller_run
}

pbench_user_benchmark() {
  local benchmark_test_config="$1"

  if test "$pbench_containerized" = y ; then
    # a containerized pbench run pbench_user_benchmark_containerized "$benchmark_test_config"
    die 1 "Containerized Pbench not yet supported."
  else
    # a regular pbench run
    if test "${PBENCH_SCRAPER_USE:-false}" = true ; then
      pbench-user-benchmark \
        -C "$benchmark_test_config" \
        --pbench-post='/usr/local/bin/pbscraper -i $benchmark_results_dir/tools-default -o $benchmark_results_dir; ansible-playbook -vv -i /root/svt/utils/pbwedge/hosts /root/svt/utils/pbwedge/main.yml -e new_file=$benchmark_results_dir/out.json -e git_test_branch='http_$benchmark_test_config \
        -- $pbench_mb_wrapper
    else
      pbench-user-benchmark -C "$benchmark_test_config" -- $pbench_mb_wrapper
    fi
  fi
}

# Run the HTTP(s) benchmark against routes in '$routes_file'.
benchmark_run() {
  local routes routes_f delay_f mb_conns_per_target conns_per_thread_f ka_f now benchmark_test_config
  local router_term mb_targets load_generator_nodes
  local run_log=run.log			# a log file for non-pbench runs
  local ret				# return value
  local benchmark_iteration_sleep=0	# sleep for some time between test iterations
  local mb_tls_session_reuse=n

  rm -f $run_log

  # Dependency checks
  if ! test -x ${EXTENDED_TEST_BIN} ; then
    die 1 "'$EXTENDED_TEST_BIN' not executable, install atomic-openshift-tests."
  fi

  load_generator_nodes=$(load_generator_nodes_get | wc -l)
  test "$load_generator_nodes" -ge 1 || die 1 "couldn't find any load generator nodes"

  test "${MB_TLS_SESSION_REUSE}" = true && mb_tls_session_reuse=y

  # All possible route terminations are: mix,http,edge,passthrough,reencrypt
  # For the purposes of CI, use "mix" only
  for route_term in ${ROUTE_TERMINATION//,/ } ; do
    case $route_term in
      mix) mb_targets="(http|edge|passthrough|reencrypt)-0.1\. (http|edge|passthrough|reencrypt)-0.[0-9]\."
      ;;
      http) mb_targets="http-0.[0-9]\."
      ;;
      edge) mb_targets="edge-0.[0-9]\."
      ;;
      passthrough) mb_targets="passthrough-0.[0-9]\."
      ;;
      reencrypt) mb_targets="reencrypt-0.[0-9]\."
      ;;
    esac

    for MB_TARGETS in $mb_targets ; do
      oc get routes --all-namespaces | awk "/${MB_TARGETS}/"'{print $3}' > $routes_file
      routes=$(wc -l < $routes_file)

      test "${routes:-0}" -eq 0 && {
        warn "no routes to test against"
        continue
      }
      routes_f=$(printf "%04d" $routes)

      for MB_DELAY in 0 ; do
        delay_f=$(printf "%04d" $MB_DELAY)

        # make sure you set 'net.ipv4.ip_local_port_range = 1000 65535' on the client machine
        if   test $routes -le 100 ; then
          mb_conns_per_target="1 40 200"
        elif test $routes -le 500 ; then
          mb_conns_per_target="1 20 80"
        elif test $routes -le 1000 ; then
          mb_conns_per_target="1 20 40"
        elif test $routes -le 2000 ; then
          mb_conns_per_target="1 10 20"
        else
          mb_conns_per_target="1"
        fi

        for MB_CONNS_PER_TARGET in $mb_conns_per_target ; do
          conns_per_thread_f=$(printf "%03d" $MB_CONNS_PER_TARGET)
          for MB_KA_REQUESTS in 1 10 100 ; do
            ka_f=$(printf "%03d" $MB_KA_REQUESTS)

            for URL_PATH in /${MB_RESPONSE_SIZE}.html ; do
              now=$(date '+%Y-%m-%d_%H.%M.%S')
              benchmark_test_config="${routes_f}r-${conns_per_thread_f}cpt-${delay_f}d_ms-${ka_f}ka-${mb_tls_session_reuse}tlsru-${RUN_TIME}s-${route_term}-${TEST_CFG}"
              RESULTS_DIR=mb-$benchmark_test_config
              echo "Running test with config: $benchmark_test_config"

              export WLG_IMAGE RUN_TIME RESULTS_DIR SERVER_RESULTS_DIR MB_DELAY MB_TARGETS MB_CONNS_PER_TARGET MB_METHOD MB_REQUEST_BODY_SIZE MB_KA_REQUESTS MB_TLS_SESSION_REUSE URL_PATH

              sed -i "s|        - num:.*|        - num: $load_generator_nodes|" config/stress-mb.yaml	# ugly hack, TODO: add support to golang cluster loader for ENV variables
              if test "$pbench_use" = true ; then
                pbench_user_benchmark "$benchmark_test_config"
              else
                RESULTS_DIR=$RESULTS_DIR-$now	# add timestamp to non-pbench test directories
                SERVER_RESULTS_DIR=$pbench_dir

                $EXTENDED_TEST_BIN --ginkgo.focus="Load cluster" --viper-config=config/stress-mb 2>&1 | tee -a $run_log
              fi

              ret=$?
              test "$SMOKE_TEST" = true -o -e "$file_quit" && return $ret
              echo "sleeping $benchmark_iteration_sleep"
              sleep $benchmark_iteration_sleep
            done
          done
        done
      done
    done
  done # route_term
}

# Process results collected in the benchmark run.
process_results() {
  local dir routes_f conns_per_thread_f delay_f ka_f tlsru_f run_time_f route_term
  local total_hits total_rps total_latency_95 target_dir
  local now=$(date '+%Y-%m-%d_%H.%M.%S')
  local archive_name=http-$now-${TEST_CFG}
  local out_dir=$pbench_dir/$archive_name

  if ! test "$pbench_use" = true ; then
    warn "processing of results is supported only for pbench runs"
    return 1
  fi

  rm -rf $out_dir
  for dir in $(find $pbench_dir -maxdepth 1 -type d -name ${pbench_prefix}????r-???cpt-????d_ms-???ka-ytlsru-*s-* | LC_COLLATE=C sort) ; do
    set $(echo $dir | sed -E 's|^.*[-_]([0-9]*)r-([0-9]*)cpt-([0-9]*)d_ms-([0-9]*)ka-([yn])tlsru-([0-9]*)s-([^-]*)-.*$|\1 \2 \3 \4 \5 \6 \7|')
    routes_f=$1
    conns_per_thread_f=$2
    delay_f=$3
    ka_f=$4
    tlsru_f=$5
    run_time_f=$6
    route_term=$7
    echo "routes=$routes_f; conns_per_thread_f=$conns_per_thread_f; delay_f=$delay_f; ka_f=$ka_f; tlsru_f=$tlsru_f; run_time_f=$run_time_f; route_term=$route_term"

    total_hits=$(awk 'BEGIN{i=0} /^200/ {i+=$2} END{print i}' $dir/mb-*/graphs/total_hits.txt 2>/dev/null)
    total_rps=$(echo "scale=3; ${total_hits:-0}/$run_time_f" | bc)
    total_latency_95=$(awk 'BEGIN{i=0} /^200/ {i=$3>i?$3:i} END{print i}' $dir/mb-*/graphs/total_latency_pctl.txt 2>/dev/null)
    target_dir=$out_dir/processed-$route_term/${routes_f}r/${conns_per_thread_f}cpt/${ka_f}ka
    mkdir -p $target_dir
    if test "$total_rps" != 0 ; then
      printf "%s\n" "$total_rps" >> $target_dir/$file_total_rps
    fi
    if test "$total_latency_95" ; then
      printf "%s\n" "$total_latency_95" >> $target_dir/$file_total_latency
    fi
  done
  # Tar-up the post-processed results and place them into the last directory (alphabetical sort)
  tar Jcvf $dir/${archive_name}.tar.xz -C $pbench_dir $archive_name
  echo "Processed results stored to: $dir"
  # Remove out_dir, Pbench post-processing doesn't like random directories like this without Pbench directory structures
  rm -rf $out_dir
}

# Move the benchmark results to a pbench server.
pbench_move_results() {
  local now=$(date '+%Y-%m-%d_%H.%M.%S')

  if test "$MOVE_RESULTS" = true ; then
    pbench-move-results --prefix="http-$now-${TEST_CFG}" 2>&1
  fi
}

# Delete all namespaces with application pods, services and routes created for the purposes of HTTP tests.
namespace_cleanup() {
  test "$NAMESPACE_CLEANUP" = true || return 0

  oc delete ns --selector $http_ns_label
}

main() {
  local fn
  local i=0

  for key in "${param_fn[@]}" ; do
    fn="${param_fn[$i]}"
    $fn
    ((i++))
  done
}

param_set

# option parsing
while true ; do
  case "$1" in
    --[Hh][Ee][Ll][Pp]|-h) usage 0
    ;;

    -*) die 1 "invalid option '$1'"
    ;;

    *)  break
    ;;
  esac
  shift
done

# parameter/task processing
while test "$1" ; do
  param="$1"
  fn=$(param2fn $param)

  if test $? -eq 0 ; then
    $fn
  elif test "$param" = "all" ; then
    main
  else
    die 1 "don't know what to do with parameter '$param'"
  fi

  shift
done

test "$param" || usage 1	# no parameters passed
