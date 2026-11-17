# FreeIPA (DC) для стенда.
# Официальный образ запускается через systemd; оборачиваем его ENTRYPOINT,
# чтобы выставить IP на data-интерфейсе ДО автоустановки ipa-server-install.
#
# Установку пакетов (dnf) не используем — репозитории могут быть недоступны.
# Для настройки интерфейса кладём статический busybox (даёт команду `ip`).
FROM busybox:stable AS tools

FROM quay.io/freeipa/freeipa-server:almalinux-9

COPY --from=tools /bin/busybox /usr/local/bin/busybox

COPY entrypoint.sh /usr/local/sbin/gis-entrypoint
RUN chmod 0755 /usr/local/sbin/gis-entrypoint

# exec-form, чтобы systemd оказался PID 1 после exec нашим скриптом
ENTRYPOINT [ "/usr/local/sbin/gis-entrypoint" ]
