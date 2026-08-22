# Vendored from hyprwm/hyprland-plugins v0.56.0 (7644cecdb947060682891a0db2a0cdc5c0b9e704).
# Hyprland 0.56.2 has no separate plugin tag; this is the pin hyprpm used.

ifeq ($(CXX),g++)
  EXTRA_FLAGS = --no-gnu-unique
else
  EXTRA_FLAGS =
endif

CXXFLAGS ?= -O2
CXXFLAGS += -shared -fPIC -std=c++2b -Wno-c++11-narrowing
INCLUDES = `pkg-config --cflags pixman-1 libdrm hyprland libinput libudev wayland-server xkbcommon`
LIBS =

SRC = main.cpp barDeco.cpp BarPassElement.cpp
TARGET = hyprbars.so
PLUGINDIR ?= /usr/lib/hyprland-plugins

all: $(TARGET)

$(TARGET): $(SRC)
	$(CXX) $(CXXFLAGS) $(LDFLAGS) $(EXTRA_FLAGS) $(INCLUDES) $^ -o $@ $(LIBS)

install: $(TARGET)
	install -Dm755 $(TARGET) $(DESTDIR)$(PLUGINDIR)/$(TARGET)

clean:
	rm -f $(TARGET)

.PHONY: all install clean
