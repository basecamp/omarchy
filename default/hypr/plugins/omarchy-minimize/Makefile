ifeq ($(CXX),g++)
  EXTRA_FLAGS = --no-gnu-unique
else
  EXTRA_FLAGS =
endif

CXXFLAGS ?= -O2
CXXFLAGS += -shared -fPIC -std=c++2b -Wno-c++11-narrowing
INCLUDES = `pkg-config --cflags pixman-1 libdrm hyprland libinput libudev wayland-server xkbcommon`
LIBS =

SRC = main.cpp
TARGET = omarchy-minimize.so
PLUGINDIR ?= /usr/lib/hyprland-plugins

all: $(TARGET)

$(TARGET): $(SRC)
	$(CXX) $(CXXFLAGS) $(LDFLAGS) $(EXTRA_FLAGS) $(INCLUDES) $^ -o $@ $(LIBS)

install: $(TARGET)
	install -Dm755 $(TARGET) $(DESTDIR)$(PLUGINDIR)/$(TARGET)

clean:
	rm -f $(TARGET)

.PHONY: all install clean
