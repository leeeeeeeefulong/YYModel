# YYModel Test Demo — Makefile
#
# Usage:
#   make          — build and run
#   make build    — build only
#   make run      — run only
#   make clean    — remove binary

CC = clang
CFLAGS = -fobjc-arc -framework Foundation -Wall -Wno-deprecated-declarations
YYMODEL_DIR = ../YYModel
SOURCES = $(YYMODEL_DIR)/YYClassInfo.m $(YYMODEL_DIR)/NSObject+YYModel.m YYModelTestModels.m main.m
INCLUDES = -I$(YYMODEL_DIR)
TARGET = yymodel_test

.PHONY: all build run clean

all: build run

build:
	$(CC) $(CFLAGS) $(INCLUDES) $(SOURCES) -o $(TARGET)
	@echo "✅ Build succeeded: $(TARGET)"

run:
	@echo "\n🚀 Running tests...\n"
	./$(TARGET)

clean:
	rm -f $(TARGET)
	@echo "🧹 Cleaned."
