#!/bin/bash
# Fails if a view shown on the overlay opens a system window: a tooltip, a menu, a context menu,
# a popover, an alert or a sheet is not covered by `sharingType = .none`, so it would show in a
# screen share. The main window (Copilote/Main, HistoryViews) may.
cd "$(dirname "$0")/.."
files=$(ls Copilote/Views/*.swift Copilote/Overlay/*.swift Copilote/Base/FicheViews.swift Copilote/App/OnboardingController.swift | grep -v HistoryViews.swift)
pattern='\.help\(|toolTip|\.contextMenu|(^|[^A-Za-z])Menu( \{|\()|\.popover\(|\.alert\(|\.sheet\(|confirmationDialog|NSMenu\(|NSAlert\(|NSPopover|NSOpenPanel|NSSavePanel|fileImporter|pickerStyle\(\.menu\)'
found=$(grep -nE "$pattern" $files | grep -v '^\s*//' | grep -vE ':\s*(//|///)')
web=$(grep -nE '\.title *=|title=' Copilote/Resources/web/overlay.js | grep -v '^\s*//')
if [ -n "$found$web" ]; then
  echo "Fenêtre système ouverte depuis l'overlay (visible au partage d'écran) :"
  echo "$found"
  echo "$web"
  exit 1
fi
echo "✓ aucune fenêtre système depuis l'overlay"
