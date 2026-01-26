#!/bin/bash
# tester.sh - TFE health check tester for GCP Marketplace verification

set -xeo pipefail
shopt -s nullglob

echo "=== TFE Marketplace Tester ==="
echo "APP_INSTANCE_NAME: ${APP_INSTANCE_NAME}"
echo "NAMESPACE: ${NAMESPACE}"

for test in /tests/*; do
  echo "Running test: ${test}"
  testrunner -logtostderr "--test_spec=${test}"
done

echo "=== All tests completed ==="
