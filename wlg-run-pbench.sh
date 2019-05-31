#!/bin/sh

# This is a wrapper script for pbench.

main() {
  # Show the configuration for the HTTP load generator
  cat <<EOF
RUN=$RUN
LOAD_GENERATORS=$LOAD_GENERATORS
RUN_TIME=$RUN_TIME
MB_DELAY=$MB_DELAY
MB_TARGETS=$MB_TARGETS
MB_CONNS_PER_TARGET=$MB_CONNS_PER_TARGET
MB_METHOD=$MB_METHOD
MB_REQUEST_BODY_SIZE=$MB_REQUEST_BODY_SIZE
MB_KA_REQUESTS=$MB_KA_REQUESTS
MB_TLS_SESSION_REUSE=$MB_TLS_SESSION_REUSE
MB_RAMP_UP=$MB_RAMP_UP
URL_PATH=$URL_PATH
SERVER_RESULTS=$SERVER_RESULTS
EOF

  test "$SERVER_RESULTS" && {
    local server_results=$(echo ${SERVER_RESULTS:6} | cut -d: -f1)
    SERVER_RESULTS="${SERVER_RESULTS:0:6}${server_results}:$benchmark_run_dir"
  }

  ./wlg-run.sh
}

main
