# Test configuration: a label to append to pbench directories and mb result directories.
export TEST_CFG=${TEST_CFG:-1router}
# A list of paths to k8s configuration files.  Colon-delimited for Linux.
export KUBECONFIG=${KUBECONFIG:-/root/.kube/config}
# Use benchmarking and performance analysis framework Pbench.
export PBENCH_USE=${PBENCH_USE:-false}
# Pbench scraper/wedge usage for r2r analysis.
export PBENCH_SCRAPER_USE=${PBENCH_SCRAPER_USE:-false}
# Clear results from previous pbench runs.
export CLEAR_RESULTS=${CLEAR_RESULTS:-true}
# Move the benchmark results to a pbench server.
export MOVE_RESULTS=${MOVE_RESULTS:-false}
# HTTP-test specifics
# Endpoint for collecting results from workload generator node(s).  Keep empty if copying is not required.
# - scp://[user@]server:[path]
# - kcp://[namespace/]pod:[path]
# Note: when PBENCH_USE=true, path is overriden by $benchmark_run_dir
export SERVER_RESULTS=${SERVER_RESULTS}
# Path to private key when using scp:// to copy results to SERVER_RESULTS.  It is mounted to workload generator container(s).
export SERVER_RESULTS_SSH_KEY=${SERVER_RESULTS_SSH_KEY:-/root/.ssh/id_rsa}
# How many workload generators to use.
export LOAD_GENERATORS=${LOAD_GENERATORS:-1}
# Load-generator nodes described by an extended regular expression (use "oc get nodes" node names).
export LOAD_GENERATOR_NODES=${LOAD_GENERATOR_NODES:-b[5-5].lan}
# Number of projects to create for each type of application (4 types currently).
export CL_PROJECTS=${CL_PROJECTS:-10}
# Number of templates to create per project.
export CL_TEMPLATES=${CL_TEMPLATES:-1}
# Run time of individual HTTP test iterations in seconds.
export RUN_TIME=${RUN_TIME:-120}
# Maximum delay between client requests in ms.
export MB_DELAY=${MB_DELAY:-0}
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
# Run only a single HTTP test to establish functionality.  It also overrides CL_PROJECTS and CL_TEMPLATES.
export SMOKE_TEST=${SMOKE_TEST:-false}
# Delete all namespaces with application pods, services and routes created for the purposes of HTTP tests.
export NAMESPACE_CLEANUP=${NAMESPACE_CLEANUP:-true}
