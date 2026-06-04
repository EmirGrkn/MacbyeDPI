CC      = clang
CFLAGS  = -O2 -Wall -Wextra -std=c11 -D_DARWIN_C_SOURCE
TARGET  = macbyedpi_dnsredir

.PHONY: all clean install uninstall

all: $(TARGET)

$(TARGET): macbyedpi_dnsredir.c
	$(CC) $(CFLAGS) -o $@ $<
	@echo ""
	@echo "Build successful: ./$(TARGET)"
	@echo "Run:  sudo ./$(TARGET) --dns-addr 77.88.8.8 --dns-port 1253"
	@echo "Or:   sudo ./setup.sh --dns-addr 77.88.8.8 --dns-port 1253"

clean:
	rm -f $(TARGET)

install: $(TARGET)
	@echo "Use setup.sh for full installation (handles DNS config + launchd)."
	@echo "Running: sudo ./setup.sh"
	@sudo ./setup.sh
