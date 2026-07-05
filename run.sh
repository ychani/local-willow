#!/bin/zsh
# Launch local-willow. First run will prompt for microphone access;
# see README.md for the Accessibility/Input Monitoring permissions.
cd "$(dirname "$0")"
exec .venv/bin/python -m willow
