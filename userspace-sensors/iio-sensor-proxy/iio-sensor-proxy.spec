Name:           iio-sensor-proxy
Version:        3.9
Release:        2.pipa%{?dist}
Summary:        IIO accelerometer sensor to input device proxy (pipa SSC fix series)

License:        GPL-3.0-or-later
URL:            https://gitlab.freedesktop.org/hadess/iio-sensor-proxy
# Built on the Pad by scripts/build-install-iio-sensor-proxy.sh from upstream
# tag 3.9 plus userspace-sensors/iio-sensor-proxy/patches. Patches are applied
# to the source tree BEFORE tarring, so the spec has no Patch tags.
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  gcc
BuildRequires:  meson
BuildRequires:  ninja-build
BuildRequires:  pkgconfig(libssc)
BuildRequires:  pkgconfig(gudev-1.0)
BuildRequires:  pkgconfig(gio-2.0)
BuildRequires:  pkgconfig(polkit-gobject-1)
Requires:       libssc
Requires:       dbus
Requires:       polkit

%description
iio-sensor-proxy 3.9 with the pipa SSC fix series:
- skip the probe close() during discovery (breaks the later open)
- fix the close() signal-handler path (kills measurement delivery)
- null-GError guards in SSC drivers
- retry the open after resume while the sensor DSP recovers
Provenance and details: SENSORS.md in pipa-fedora-builder-43.

%prep
%setup -q

%build
meson setup . build --prefix %{_prefix} -Dssc-support=enabled -Dtests=false -Dgtk_doc=false
ninja -C build

%install
DESTDIR=%{buildroot} ninja -C build install

%files
%license COPYING
%{_libexecdir}/iio-sensor-proxy
%{_bindir}/monitor-sensor
%{_prefix}/lib/systemd/system/iio-sensor-proxy.service
%{_udevrulesdir}/80-iio-sensor-proxy.rules
%{_datadir}/dbus-1/system.d/*
