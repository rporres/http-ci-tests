#!/bin/bash

ProgramName=${0##*/}

. ./env.sh

### Global variables ###########################################################
param_name=()			# parameters, name
param_fn=()			# parameters, function name
param_hlp=()			# parameters, help
http_pod_label=test=http	# label for application pods
http_server=nginx		# backend server for http tests (h2o|nginx)
declare -a a_region		# array of old node region labels

# pbench-specific variables ####################################################
wlg_run=./wlg-run.sh
wlg_run_pbench=./wlg-run-pbench.sh
file_total_rps=rps.txt
file_total_latency=latency_95.txt
file_quit=quit				# if this file is detected during test runs, abort

# mb-specific variables ########################################################
routes_file=routes.txt		# a file with routes to pass to cluster loader

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
    i=$((i+1))
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
    i=$((i+1))
  done << _PARAM_
environment-dump|environment_dump|Dump the environment for the purposes of re-running some of the test iterations manually.
router_liveness_probe-disable|router_liveness_probe|Increase period seconds for the router liveness probe.
load_generator-label|load_generator_nodes_label|Label and taint the node(s) for the load generator pod(s).
pbench-clear-results|pbench_clear_results|Clear results from previous pbench runs.
cluster-load|cl_load|Populate the cluster with application pods and routes.
benchmark-run|benchmark_run|Run the HTTP(s) benchmark against routes in '$routes_file'.
process-results|process_results|Process results collected in the benchmark run.
results-move|pbench_move_results|Move the benchmark results to a pbench server.
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
    i=$((i+1))
  done

  return 1
}

shell_expand_file() {
  local file="$1"
  local data=$(< "$file")
  local delimiter="__shell_expand_file__"
  local command="cat <<$delimiter"$'\n'"$data"$'\n'"$delimiter"
  eval "$command"
}

environment_dump() {
  shell_expand_file env.sh > env-dump.sh
}

check_admin() {
  local oc_whoami=`oc whoami`
  local oc_admin_user=system:admin

  test "$oc_whoami" = "$oc_admin_user"
}

# Increase period seconds for the router liveness probe.
router_liveness_probe() {
  local deployment selector d probe_set

  check_admin || {
    echo "Not changing liveness probe, cluster admin needed."
    return 0
  }

  # Increase period seconds for the router liveness probe.
  for deployment in dc deployment
  do
    for selector in router=router app=router ingress.openshift.io/clusteringress=default ingresscontroller.operator.openshift.io/owning-ingresscontroller=default
    do
      for d in $(oc get $deployment --selector=$selector --template='{{range .items}}{{.metadata.name}}|{{.metadata.namespace}}{{"\n"}}{{end}}' --all-namespaces)
      do
        set -- ${d//|/ }
        d_name=$1
        d_namespace=$2
        oc set probe $deployment/$d_name --liveness --period-seconds=$HTTP_TEST_RUNTIME -n=$d_namespace
        # Alternatively, delete the router liveness probe.
        #oc set probe $deployment/$d_name --liveness --remove -n=$d_namespace
        probe_set=true
      done
    done
  done

  test "$probe_set" || die 1 "Couldn't set router liveness probe."
}

load_generator_nodes_get() {
  oc get nodes --no-headers | awk '{print $1}' | grep -E "${HTTP_TEST_LOAD_GENERATOR_NODES}"
}

results_dir_get() {
  local pbench_agent_dir=/var/lib/pbench-agent
  local server_results_dir=$(echo ${HTTP_TEST_SERVER_RESULTS:6} | cut -d: -f2-)

  # scp://user@server:
  test -z "$server_results_dir" && server_results_dir=$HOME
  # scp://user@server   (invalid spec, colon is required!)
  test "$server_results_dir" = "${HTTP_TEST_SERVER_RESULTS:6}" && server_results_dir=$pbench_agent_dir
  test "${PBENCH_USE}" = true && server_results_dir=$pbench_agent_dir

  echo $server_results_dir
  return 0
}

load_generator_nodes_label_taint() {
  local label="${1:-y}" # unlabel/remove taint if not 'y'
  local i node placement taint region region_old
  local oc_whoami=`oc whoami`

  test "$HTTP_TEST_LOAD_GENERATOR_NODES" || {
    echo "Not (un)labelling nodes, load generator nodes unspecified."
    return 0
  }

  check_admin || {
    echo "Not (un)labelling nodes, cluster admin needed."
    return 0
  }

  if test "$label" = y ; then
    placement=test=wlg
    taint=test=wlg:NoSchedule
  else
    placement=test-
    taint=test-
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
    oc label node $node $placement --overwrite
    oc label node $node $region --overwrite
    oc adm taint nodes $node $taint --overwrite
    i=$((i+1))
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

# Clear results from previous pbench runs.
pbench_clear_results() {
  test "${PBENCH_USE}" = true || return 0

  if test "${PBENCH_CLEAR_RESULTS}" = "true" ; then
    pbench-clear-results
  fi
}

cl_max_pods_not_running() {
  local max_not_running="${1:-20}"
  local project="${2:-default}"
  local not_running

  while true ; do
    not_running=$(oc get pods --selector $http_pod_label --no-headers -n=$project | grep -E -v '(Running|Completed|Unknown)' -c)
    test "$not_running" -le "$max_not_running" && break
    echo "$not_running pods not running"
    sleep 1
  done
}

cl_new_project_or_reuse() {
  local project="$1"
  local res

  if oc get project $project >/dev/null 2>&1 ; then
    # $project exists, recycle it
    for res in rc dc bc pod service route ; do
      oc delete $res --all -n=$project >/dev/null 2>&1
    done
  else
    # $project doesn't exist
    oc new-project $project --skip-config-write
  fi
}

# Populate the cluster with application pods and routes.
cl_load() {
  local server_quickstart_dir="content/quickstarts/$http_server"
  local templates="$server_quickstart_dir/server-http.yaml $server_quickstart_dir/server-tls-edge.yaml $server_quickstart_dir/server-tls-passthrough.yaml $server_quickstart_dir/server-tls-reencrypt.yaml"
  local projects=${HTTP_TEST_APP_PROJECTS:-10}		# 10, 30, 60, 180
  local project_start=1
  local templates_total=${HTTP_TEST_APP_TEMPLATES:-50}	# number of templates per project
  local templates_start=1			# do not change or read the code to make sure it does what you want

  local project project_basename template p p_f i i_f

  test "${HTTP_TEST_SMOKE_TEST}" = true && {
    # override the number of projects and templates if this is just a smoke test
    projects=2
    templates_total=2
  }

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
        oc process \
          -pIDENTIFIER=$i_f \
          -pHTTP_TEST_SERVER_CONTAINER_IMAGE=$HTTP_TEST_SERVER_CONTAINER_IMAGE \
          -f $template \
          -n=$project | oc create -f- -n=$project
        i=$((i+1))

        cl_max_pods_not_running 20 $project
      done
    done
  done
}

pbench_user_benchmark() {
  local benchmark_test_config="$1"

  # a regular pbench run
  if test "${PBENCH_SCRAPER_USE}" = true ; then
    pbench-user-benchmark \
      --sysinfo=none \
      -C "$benchmark_test_config" \
      --pbench-post='/usr/local/bin/pbscraper -i $benchmark_results_dir/tools-default -o $benchmark_results_dir; ansible-playbook -vv -i /root/svt/utils/pbwedge/hosts /root/svt/utils/pbwedge/main.yml -e new_file=$benchmark_results_dir/out.json -e git_test_branch='http_$benchmark_test_config \
      -- $wlg_run_pbench
  else
    pbench-user-benchmark --sysinfo=none -C "$benchmark_test_config" -- $wlg_run_pbench
  fi
}

# Run the HTTP(s) benchmark against routes in '$routes_file'.
benchmark_run() {
  local routes routes_f delay_f mb_conns_per_target conns_per_thread_f ka_f now benchmark_test_config
  local router_term mb_targets load_generator_nodes
  local run_log=run.log			# a log file for non-pbench runs
  local ret				# return value
  local benchmark_iteration_sleep=30	# sleep for some time between test iterations
  local mb_tls_session_reuse=n

  rm -f $run_log

  test "${HTTP_TEST_LOAD_GENERATORS}" -ge 1 || die 1 "workload generator count (${HTTP_TEST_LOAD_GENERATORS}) is not >= 1"

  test "${HTTP_TEST_MB_TLS_SESSION_REUSE}" = true && mb_tls_session_reuse=y

  # Interface HTTP_TEST_STRESS_CONTAINER_IMAGE with the current environment
  export MB_DELAY MB_TARGETS MB_CONNS_PER_TARGET MB_KA_REQUESTS URL_PATH

  # All possible route terminations are: mix,http,edge,passthrough,reencrypt
  # For the purposes of CI, use "mix" only
  for route_term in ${HTTP_TEST_ROUTE_TERMINATION//,/ } ; do
    case $route_term in
      mix) mb_targets="(http|edge|passthrough|reencrypt)-0.1[.] (http|edge|passthrough|reencrypt)-0.[0-9][.]"	# don't use "\.", issues with yaml files
      ;;
      http) mb_targets="http-0.[0-9][.]"
      ;;
      edge) mb_targets="edge-0.[0-9][.]"
      ;;
      passthrough) mb_targets="passthrough-0.[0-9][.]"
      ;;
      reencrypt) mb_targets="reencrypt-0.[0-9][.]"
      ;;
    esac

    for MB_TARGETS in $mb_targets ; do
      # get all the routes from all namespaces we know about (don't rely on --all-namespaces, we might not have access to resources at cluster scope)
      rm -f $routes_file
      for p in $(oc get projects -o template --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}' | \
                   grep -E '^server-(http|tls-(edge|passthrough|reencrypt))-[0-9]+$')
      do
        oc get routes -n=$p --no-headers | awk "/${MB_TARGETS}/"'{print $2}' >> $routes_file
      done

      routes=$(wc -l < $routes_file)

      test "${routes:-0}" -eq 0 && {
        warn "no routes to test against"
        continue
      }
      routes_f=$(printf "%04d" $routes)

      for MB_DELAY in ${HTTP_TEST_MB_DELAY//,/ } ; do
        delay_f=$(printf "%04d" $MB_DELAY)

        # make sure you set 'net.ipv4.ip_local_port_range = 1024 65535' on the client machine
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

            for URL_PATH in /${HTTP_TEST_MB_RESPONSE_SIZE}.html ; do
              now=$(date '+%Y-%m-%d_%H.%M.%S')
              benchmark_test_config="${routes_f}r-${conns_per_thread_f}cpt-${delay_f}d_ms-${ka_f}ka-${mb_tls_session_reuse}tlsru-${HTTP_TEST_RUNTIME}s-${route_term}-${HTTP_TEST_SUFFIX}"
              echo "Running test with config: $benchmark_test_config"

              if test "$PBENCH_USE" = true ; then
                pbench_user_benchmark "$benchmark_test_config" || die $? "Test iteration with Pbench failed with exit code: $?"
              else
                # a test run without Pbench
                test "$HTTP_TEST_SERVER_RESULTS" && {
                  local server_results=$(echo ${HTTP_TEST_SERVER_RESULTS:6} | cut -d: -f1)
                  local server_results_dir=$(echo ${HTTP_TEST_SERVER_RESULTS:6} | cut -d: -f2-)
                  local abs_path_prefix

                  test "${server_results_dir}" && abs_path_prefix=/
                  HTTP_TEST_SERVER_RESULTS="${HTTP_TEST_SERVER_RESULTS:0:6}${server_results}:${server_results_dir%/}${abs_path_prefix}$benchmark_test_config"
                }

		$wlg_run 2>&1 || die $? "Test iteration failed with exit code: $?"
              fi

              ret=$?
              test "$HTTP_TEST_SMOKE_TEST" = true -o -e "$file_quit" && return $ret
              echo "sleeping $benchmark_iteration_sleep"
              sleep $benchmark_iteration_sleep
            done
          done
        done
      done	# HTTP_TEST_MB_DELAY
    done
  done # route_term
}

# Process results collected in the benchmark run.
process_results() {
  local dir routes_f conns_per_thread_f delay_f ka_f tlsru_f run_time_f route_term
  local total_hits total_rps total_latency_95 target_dir
  local now=$(date '+%Y-%m-%d_%H.%M.%S')
  local archive_name=http-$now-${HTTP_TEST_SUFFIX}
  local results_dir=$(results_dir_get)
  local out_dir=$results_dir/$archive_name

  test "${HTTP_TEST_SERVER_RESULTS}" || return 0

  rm -rf $out_dir
  for dir in $(find $results_dir -maxdepth 1 -type d -name *[0-9]r-*[0-9]cpt-*[0-9]d_ms-*[0-9]ka-ytlsru-*s-* | LC_COLLATE=C sort) ; do
    set $(echo $dir | sed -E 's|^.*[^0-9]([0-9]{1,})r-([0-9]{1,})cpt-([0-9]{1,})d_ms-([0-9]{1,})ka-([yn])tlsru-([0-9]{1,})s-([^-]*)-.*$|\1 \2 \3 \4 \5 \6 \7|')
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
  tar Jcvf $dir/${archive_name}.tar.xz -C $results_dir $archive_name
  echo "Processed results stored to: $dir"
  # Remove out_dir, Pbench post-processing doesn't like random directories like this without Pbench directory structures
  rm -rf $out_dir
}

# Move the benchmark results to a pbench server.
pbench_move_results() {
  local now=$(date '+%Y-%m-%d_%H.%M.%S')

  test "${PBENCH_USE}" = true || return 0

  if test "${PBENCH_MOVE_RESULTS}" = true ; then
    echo "Starting pbench-move-results on `hostname` to `pbench-move-results --show-server`"
    pbench-move-results --prefix="http-$now-${HTTP_TEST_SUFFIX}" 2>&1
  fi
}

# Delete all namespaces with application pods, services and routes created for the purposes of HTTP tests.
namespace_cleanup() {
  test "${HTTP_TEST_NAMESPACE_CLEANUP}" = true || return 0

  # a user might not have the privileges to do selector-based namespace deletion, go through his/her projects and
  # do a project-name cleanup
  oc get projects -o template --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}' | \
    grep -E '^server-(http|tls-(edge|passthrough|reencrypt))-[0-9]+$' | xargs oc delete project
}

main() {
  local fn
  local i=0

  for key in "${param_fn[@]}" ; do
    fn="${param_fn[$i]}"
    $fn || die 1 "failed to run $fn"
    i=$((i+1))
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

test "$1" || usage 1	# no parameters passed

# parameter/task processing
while test "$1" ; do
  param="$1"
  fn=$(param2fn $param)

  if test $? -eq 0 ; then
    $fn || die 1 "failed to run $fn"
  elif test "$param" = "all" ; then
    main || die 1 "failed to run $fn"
  else
    die 1 "don't know what to do with parameter '$param'"
  fi

  shift
done
