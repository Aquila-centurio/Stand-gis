# АРМ с графикой: Xvfb + openbox + x11vnc + noVNC + Firefox.
FROM gis/linux:latest

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      xvfb openbox x11vnc firefox-esr novnc websockify xterm dbus-x11 openvpn \
      freeipa-client libpam-mkhomedir \
 && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /gis-entrypoint.sh
COPY vpn-up.sh /usr/local/bin/vpn-up
# Заглушки системных утилит systemd/redhat-платформы для ipa-client-install
COPY hostnamectl-wrapper /usr/bin/hostnamectl
COPY systemctl-wrapper /usr/bin/systemctl
COPY authselect-wrapper /usr/bin/authselect
RUN chmod 0755 /gis-entrypoint.sh /usr/local/bin/vpn-up \
      /usr/bin/hostnamectl /usr/bin/systemctl /usr/bin/authselect

ENTRYPOINT [ "/gis-entrypoint.sh" ]
