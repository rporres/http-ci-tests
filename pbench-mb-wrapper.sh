#!/bin/sh

# This is a golang cluster loader wrapper script for pbench.

# Show the configuration for the HTTP load generator
cat <<EOF
WLG_IMAGE=$WLG_IMAGE
RUN_TIME=$RUN_TIME
RESULTS_DIR=$RESULTS_DIR
MB_DELAY=$MB_DELAY
MB_TARGETS=$MB_TARGETS
MB_CONNS_PER_TARGET=$MB_CONNS_PER_TARGET
MB_METHOD=$MB_METHOD
MB_REQUEST_BODY_SIZE=$MB_REQUEST_BODY_SIZE
MB_KA_REQUESTS=$MB_KA_REQUESTS
MB_TLS_SESSION_REUSE=$MB_TLS_SESSION_REUSE
URL_PATH=$URL_PATH
EOF

export SERVER_RESULTS_DIR=$benchmark_run_dir	# /var/lib/pbench-agent/xyz defined by pbench
$EXTENDED_TEST_BIN --ginkgo.focus="Load cluster" --viper-config=config/stress-mb
