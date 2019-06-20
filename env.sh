set -a
# A list of paths to k8s configuration files.  Colon-delimited for Linux.
KUBECONFIG=${KUBECONFIG:-/root/.kube/config}
# Use benchmarking and performance analysis framework Pbench.
PBENCH_USE=${PBENCH_USE:-false}
# Pbench scraper/wedge usage for r2r analysis.
PBENCH_SCRAPER_USE=${PBENCH_SCRAPER_USE:-false}
# Clear results from previous pbench runs.
PBENCH_CLEAR_RESULTS=${PBENCH_CLEAR_RESULTS:-true}
# Move the benchmark results to a pbench server.
PBENCH_MOVE_RESULTS=${PBENCH_MOVE_RESULTS:-false}

# HTTP-test specifics
# Test configuration: a label to append to pbench directories and mb result directories.
HTTP_TEST_SUFFIX=${HTTP_TEST_SUFFIX:-1router}
# Endpoint for collecting results from workload generator node(s).  Keep empty if copying is not required.
# - scp://[user@]server:[path]
# - kcp://[namespace/]pod:[path]
# Note: when PBENCH_USE=true, path is overriden by benchmark_run_dir environment variable
HTTP_TEST_SERVER_RESULTS=${HTTP_TEST_SERVER_RESULTS}
# Path to private key when using scp:// to copy results to HTTP_TEST_SERVER_RESULTS.  It is mounted to workload generator container(s).
HTTP_TEST_SERVER_RESULTS_SSH_KEY=${HTTP_TEST_SERVER_RESULTS_SSH_KEY:-/root/.ssh/id_rsa}
# How many workload generators to use.
HTTP_TEST_LOAD_GENERATORS=${HTTP_TEST_LOAD_GENERATORS:-1}
# Load-generator nodes described by an extended regular expression (use "oc get nodes" node names).
# If unset/empty, do not pin the workload generators to any nodes.
HTTP_TEST_LOAD_GENERATOR_NODES=${HTTP_TEST_LOAD_GENERATOR_NODES}
# Number of projects to create per each type of application template (4 templates currently).
HTTP_TEST_APP_PROJECTS=${HTTP_TEST_APP_PROJECTS:-10}
# Number of application templates to process per project.
HTTP_TEST_APP_TEMPLATES=${HTTP_TEST_APP_TEMPLATES:-1}
# Run time of individual HTTP test iterations in seconds.
HTTP_TEST_RUNTIME=${HTTP_TEST_RUNTIME:-120}
# Thread ramp-up time in seconds.  Must be < HTTP_TEST_RUNTIME.
HTTP_TEST_MB_RAMP_UP=${HTTP_TEST_MB_RAMP_UP:-0}
# Maximum delay between client requests in ms.  Can be a list of numbers separated by commas.
HTTP_TEST_MB_DELAY=${HTTP_TEST_MB_DELAY:-0}
# Use TLS session reuse.
HTTP_TEST_MB_TLS_SESSION_REUSE=${HTTP_TEST_MB_TLS_SESSION_REUSE:-true}
# HTTP method to use for backend servers (GET/POST).
HTTP_TEST_MB_METHOD=${HTTP_TEST_MB_METHOD:-GET}
# Backend server (200 OK) response document length.
HTTP_TEST_MB_RESPONSE_SIZE=${HTTP_TEST_MB_RESPONSE_SIZE:-1024}
# Body length of POST requests in characters for backend servers.
HTTP_TEST_MB_REQUEST_BODY_SIZE=${HTTP_TEST_MB_REQUEST_BODY_SIZE:-1024}
# Perform the test for the following (comma-separated) route terminations: mix,http,edge,passthrough,reencrypt
HTTP_TEST_ROUTE_TERMINATION=${HTTP_TEST_ROUTE_TERMINATION:-mix}
# Run only a single HTTP test to establish functionality.  It also overrides HTTP_TEST_APP_PROJECTS and HTTP_TEST_APP_TEMPLATES.
HTTP_TEST_SMOKE_TEST=${HTTP_TEST_SMOKE_TEST:-false}
# Delete all namespaces with application pods, services and routes created for the purposes of HTTP tests.
HTTP_TEST_NAMESPACE_CLEANUP=${HTTP_TEST_NAMESPACE_CLEANUP:-true}
# HTTP workload generator container image
HTTP_TEST_STRESS_CONTAINER_IMAGE=${HTTP_TEST_STRESS_CONTAINER_IMAGE:-quay.io/openshift-scale/http-stress}
# HTTP server container image
HTTP_TEST_SERVER_CONTAINER_IMAGE=${HTTP_TEST_SERVER_CONTAINER_IMAGE:-quay.io/openshift-scale/nginx}
set +a
