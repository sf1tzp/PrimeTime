
build:
  swift build && codesign --force --sign "TraggoMenuApp Dev" .build/debug/TraggoMenuBar

run-dev: build
  ./.build/debug/TraggoMenuBar
