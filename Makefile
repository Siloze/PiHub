SHELL := /bin/sh
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
MANAGER_SRC := $(ROOT)/pihub-manager/src
APP_PATH := $(ROOT)/PiHubManager.app
export PYTHONPATH := $(MANAGER_SRC)

.DEFAULT_GOAL := help
.PHONY: help check manager manager-build manager-open manager-reload manager-status test package-source

help:
	@printf '\n%s\n' "PiHub — gestionnaire d’IA pour macOS"
	@printf '%s\n' \
	  "  make manager          Construire puis ouvrir l’application" \
	  "  make manager-build    Construire l’application" \
	  "  make manager-open     Ouvrir l’application déjà construite" \
	  "  make manager-reload   Reconstruire puis relancer le manager" \
	  "  make manager-status   Diagnostic du manager (JSON)" \
	  "  make check            Vérifier les prérequis de développement" \
	  "  make test             Tester le backend" \
	  "  make package-source   Créer une archive des sources à partager" \
	  "" \
	  "Providers, agents et modèles se gèrent dans l’application."

check:
	@test "$$(uname -s)" = Darwin || { echo "macOS est requis pour construire l’application."; exit 1; }
	@test "$$(uname -m)" = arm64 || { echo "Apple Silicon est requis."; exit 1; }
	@xcode-select -p >/dev/null 2>&1 || { echo "Installez les outils Apple : xcode-select --install"; exit 1; }
	@xcrun --find swiftc >/dev/null
	@/usr/bin/python3 -c 'import sys; assert sys.version_info >= (3, 9), "Python 3.9+ requis"'
	@command -v rsync >/dev/null
	@printf '%s\n' "Prérequis de développement disponibles."

manager: manager-build
	@$(MAKE) --no-print-directory manager-open

manager-build: check
	@zsh "$(ROOT)/pihub-manager/build-swift.sh"

manager-open:
	@test -x "$(APP_PATH)/Contents/MacOS/PiHubManager" || { echo "Construisez d’abord avec make manager-build."; exit 1; }
	@open -g "$(APP_PATH)"

manager-reload: manager-build
	@osascript -e 'if application id "com.pihub.manager" is running then tell application id "com.pihub.manager" to quit'
	@$(MAKE) --no-print-directory manager-open

manager-status:
	@/usr/bin/python3 -m pihub_manager.hub snapshot

test:
	@cd "$(MANAGER_SRC)" && /usr/bin/python3 -m unittest discover -s "$(ROOT)/pihub-manager/tests" -v

package-source:
	@/usr/bin/python3 -m pihub_manager.hub.release
