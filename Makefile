# Makefile for Mole

.PHONY: all clean macos-app

all: macos-app

clean:
	@echo "Cleaning build artifacts..."
	rm -rf build/

macos-app:
	./scripts/build-macos-app.sh
