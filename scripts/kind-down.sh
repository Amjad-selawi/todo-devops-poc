#!/usr/bin/env bash
# Deletes the local cluster and everything in it.
set -euo pipefail
kind delete cluster --name poc
