TAPDEV = tap0
TAPADDR = 192.0.2.1/24
UPLINK = $(shell ip route get 8.8.8.8 2>/dev/null | awk '/dev/{for(i=1;i<=NF;i++) if($$i=="dev") print $$(i+1)}')

CFLAGS += -g -W -Wall -Wno-unused-parameter
INCFLAGS += -iquote .

ifeq ($(shell uname),Linux)
  # Linux specific settings
  PLATFORM := ./platform/linux
  LDFLAGS += -pthread
  INCFLAGS += -iquote $(PLATFORM)
endif

ifeq ($(shell uname),Darwin)
  # macOS specific settings
endif

EXCLUDE := -path ./platform -prune -o \
           -path ./test -prune -o \

SRCS := $(shell find . $(PLATFORM) $(EXCLUDE) -type f -name '*.c' -print | sort -V)
TARGETS := $(shell find ./test -type f -name '*.c' -print | sort -V)

OBJS := $(SRCS:%.c=%.o)
EXES := $(TARGETS:%.c=%.exe)

DEPDIR := .deps
$(shell mkdir $(DEPDIR) > /dev/null 2>&1 || :)
DEPFLAGS = -MMD -MP -MF $(DEPDIR)/$(@F:.o=.d)

.SUFFIXES:
.SUFFIXES: .c .o

.PHONY: all clean tap untap

all: $(EXES)

$(EXES): %.exe : %.o $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

.c.o:
	$(CC) $(DEPFLAGS) $(CFLAGS) $(INCFLAGS) -c $< -o $@

clean: untap
	rm -rf $(EXES) $(EXES:.exe=.o) $(OBJS) $(DEPDIR)

untap:
	@sudo iptables -C FORWARD -o $(TAPDEV) -j ACCEPT 2>/dev/null \
	  && sudo iptables -D FORWARD -o $(TAPDEV) -j ACCEPT || true
	@sudo iptables -C FORWARD -i $(TAPDEV) -j ACCEPT 2>/dev/null \
	  && sudo iptables -D FORWARD -i $(TAPDEV) -j ACCEPT || true
	@sudo iptables -t nat -C POSTROUTING -s 192.0.2.0/24 -o $(UPLINK) -j MASQUERADE 2>/dev/null \
	  && sudo iptables -t nat -D POSTROUTING -s 192.0.2.0/24 -o $(UPLINK) -j MASQUERADE || true
	@sudo ip tuntap del mode tap name $(TAPDEV) 2>/dev/null || true

tap:
	@ip addr show $(TAPDEV) 2>/dev/null || (echo "Create '$(TAPDEV)'"; \
	  sudo ip tuntap add mode tap user $(USER) name $(TAPDEV); \
	  sudo sysctl -w net.ipv6.conf.$(TAPDEV).disable_ipv6=1; \
	  sudo ip addr add $(TAPADDR) dev $(TAPDEV); \
	  sudo ip link set $(TAPDEV) up; \
	  ip addr show $(TAPDEV); \
	)
	@sudo bash -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
	@sudo iptables -C FORWARD -o $(TAPDEV) -j ACCEPT 2>/dev/null \
	  || sudo iptables -A FORWARD -o $(TAPDEV) -j ACCEPT
	@sudo iptables -C FORWARD -i $(TAPDEV) -j ACCEPT 2>/dev/null \
	  || sudo iptables -A FORWARD -i $(TAPDEV) -j ACCEPT
	@sudo iptables -t nat -C POSTROUTING -s 192.0.2.0/24 -o $(UPLINK) -j MASQUERADE 2>/dev/null \
	  || sudo iptables -t nat -A POSTROUTING -s 192.0.2.0/24 -o $(UPLINK) -j MASQUERADE

include $(wildcard $(DEPDIR)/*)
