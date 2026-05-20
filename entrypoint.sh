#!/bin/sh
# Scanner registrieren
brsaneconfig4 -a name=Brother_Scanner model=MFC-7360N ip=$BRSCAN_IP

# Dienste starten
dbus-daemon --system --fork
sed -i 's/#enable-dbus=yes/enable-dbus=yes/g' /etc/avahi/avahi-daemon.conf
avahi-daemon -D

# AirSane starten
exec airsaned --listen-port=8095 --access-log=-