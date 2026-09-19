#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/scripts/common.sh"
[[ $(uname -s) == Linux ]] || die 'Run setup and collection inside the Linux VM, not macOS.'
[[ $# -le 1 ]] || die 'Usage: bash setup.sh [--install-system]'
case ${1:-} in ''|--install-system) ;; *) die 'Usage: bash setup.sh [--install-system]' ;; esac
require_tools flock sha256sum
lock_workflow
clean_python_env
cd "$ROOT"

if [[ ${1:-} == --install-system ]]; then
    require_tools apt-get
    elevated=()
    if (( EUID != 0 )); then require_tools sudo; elevated=(sudo); fi
    "${elevated[@]}" apt-get update
    "${elevated[@]}" apt-get install -y python3-dbg python3-venv python3-dev \
        build-essential linux-tools-common libc6-dbg perl util-linux gzip
    # The running kernel needs its matching perf package, including -kvm kernels.
    "${elevated[@]}" apt-get install -y "linux-tools-$(uname -r)" || \
        die 'Matching perf package unavailable. Install perf for the running VM kernel, then rerun setup.'
fi
require_tools python3-dbg perf perl gzip
perf --version >/dev/null || die 'perf is installed as a launcher but has no tool for this kernel.'
python3-dbg - <<'PY'
import sys, sysconfig
if sys.version_info < (3,10) or not sysconfig.get_config_var('Py_DEBUG'):
    raise SystemExit('python3-dbg must be a debug CPython >=3.10.')
PY
if [[ ! -d .venv ]]; then python3-dbg -m venv .venv; fi
[[ -x .venv/bin/python ]] || die 'Existing .venv is incomplete; move it aside and rerun setup.'
# This name is an alias, not a runtime debug flag.
if [[ ! -e .venv/bin/python3-dbg ]]; then ln -s python .venv/bin/python3-dbg; fi
"$PY" - <<'PY'
import sysconfig
if not sysconfig.get_config_var('Py_DEBUG'):
    raise SystemExit('Existing .venv is release Python. Move it aside and rerun setup.')
PY
printf 'Installing pinned framework dependencies (setup only)...\n'
"$PY" -m pip install -r requirements.txt
validate_python
"$PY" -m pyperformance list --manifest manifests/timing.manifest --benchmarks nbody,raytrace
worker="$ROOT/$(worker_python)"
worker_env=$(dirname -- "$(dirname -- "$worker")")
transport=''
for name in HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY http_proxy https_proxy all_proxy no_proxy \
    PIP_INDEX_URL PIP_EXTRA_INDEX_URL PIP_TRUSTED_HOST PIP_CERT PIP_CLIENT_CERT PIP_CONFIG_FILE \
    PIP_FIND_LINKS PIP_NO_INDEX REQUESTS_CA_BUNDLE SSL_CERT_FILE; do
    if [[ -v "$name" ]]; then transport+="${transport:+,}$name"; fi
done
inherit=()
if [[ -n "$transport" ]]; then inherit=(--inherit-environ "$transport"); fi
if [[ ! -x "$worker" ]]; then
    "$PY" -m pyperformance venv create --venv "$worker_env" \
        --manifest manifests/timing.manifest --benchmarks nbody,raytrace "${inherit[@]}"
fi
"$worker" -m pip install pyperf==2.10.0 psutil==7.0.0
if [[ ! -e "$worker_env/bin/python3-dbg" ]]; then
    ln -s python "$worker_env/bin/python3-dbg"
fi
validate_worker
write_source_hashes > .prepared.sha256
printf 'Setup complete. Next: bash collect.sh all\nNo benchmark measurements were collected by setup.\n'
