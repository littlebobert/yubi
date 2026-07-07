#!/bin/sh
set -eu

ROOT_DIR="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
VENV_DIR="${ROOT_DIR}/.venv"
OUTPUT_PATH="${ROOT_DIR}/YubiKeyboard/Generated/WordFrequencies.json"
LIMIT="${1:-30000}"

if [ ! -x "${VENV_DIR}/bin/python" ]; then
  python3 -m venv "${VENV_DIR}"
fi

if ! "${VENV_DIR}/bin/python" -c "import wordfreq" >/dev/null 2>&1; then
  PIP_DISABLE_PIP_VERSION_CHECK=1 "${VENV_DIR}/bin/python" -m pip install --quiet wordfreq
fi

"${VENV_DIR}/bin/python" "${ROOT_DIR}/Scripts/generate_word_frequencies.py" "${OUTPUT_PATH}" "${LIMIT}"
