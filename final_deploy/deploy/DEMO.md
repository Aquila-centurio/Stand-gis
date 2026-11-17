# Демонстрация работы стенда ГИС (ПАСОИБ)

## 1. Общая связность (МЭ и сегменты)

### fw1 — внешний межсетевой экран (nftables + NAT)

```sh
docker exec clab-gis-fw1 ip -br addr          # eth1=198.51.100.1/24, eth2=10.10.10.1/24
docker exec clab-gis-fw1 ip route
docker exec clab-gis-fw1 nft list ruleset      # политика forward=drop + правила NAT
```

Ожидаемо: `eth1=198.51.100.1/24`, `eth2=10.10.10.1/24`; в `forward` разрешены
`ДМЗ→WAN`, публикация `web:80/443` и `vpn:1194/udp`; в `table ip nat` — `masquerade`.

### fw2 — внутренний межсетевой экран

```sh
docker exec clab-gis-fw2 ip -br addr          # eth1=10.10.10.2/24, eth2=10.10.20.1/24
docker exec clab-gis-fw2 nft list ruleset      # LAN→DMZ + DMZ→IPA:53/389/636 + VPN→LAN
```

### Маршрутизация между сегментами

```sh
docker exec clab-gis-fw1 ping -c2 10.10.10.11   # fw1 -> web (ДМЗ)
docker exec clab-gis-fw2 ping -c2 10.10.20.10   # fw2 -> ipa (внутренняя сеть)
```

### Коммутаторы сегментов (bridge + SPAN для IDS)

```sh
docker exec clab-gis-ext-sw bridge link show
docker exec clab-gis-lan-sw bridge link show
docker exec clab-gis-dmz-sw bridge link show
# SPAN: зеркалирование портов ДМЗ на сенсор to-ids
docker exec clab-gis-dmz-sw tc filter show dev to-fw1 ingress
```
## 2. DNS (единый резолвер стенда)

### dns — резолвер ДМЗ (unbound)

```sh
docker exec clab-gis-dns dig +short example.com      @127.0.0.1   # 198.51.100.80 (внешнее имя -> ext-web)
docker exec clab-gis-dns dig +short ipa.otlichnik.lab @127.0.0.1  # 10.10.20.10 (зона -> FreeIPA)
docker exec clab-gis-dns dig +short arm.otlichnik.lab @127.0.0.1  # 10.10.20.12
```

### ext-dns — имитация DNS интернета (dnsmasq, catch-all)

```sh
docker exec clab-gis-ext-dns dig +short test.example.net @127.0.0.1   # 198.51.100.80
```

### Проверка с АРМ (резолвинг идёт через `10.10.10.10`)

```sh
docker exec clab-gis-arm getent hosts example.com ipa.otlichnik.lab
```
## 3. FreeIPA (DC: Kerberos / LDAP / DNS)

```sh
# Kerberos
docker exec clab-gis-ipa bash -c 'echo Secret123 | kinit admin && klist'

# Пользователи каталога (сервисный radius, тестовый testuser)
docker exec clab-gis-ipa bash -c 'echo Secret123 | kinit admin 2>/dev/null && ipa user-find'

# АРМ зарегистрирован как host
docker exec clab-gis-ipa bash -c 'echo Secret123 | kinit admin 2>/dev/null && ipa host-find'

# DNS-запись АРМ
docker exec clab-gis-ipa bash -c 'echo Secret123 | kinit admin 2>/dev/null && ipa dnsrecord-show otlichnik.lab arm'
```

Ожидаемо: `admin@OTLICHNIK.LAB`; пользователи `radius` и `testuser`;
хосты `ipa.otlichnik.lab` и `arm.otlichnik.lab`.

---

## 4. БД (PostgreSQL)

```sh
docker exec clab-gis-db pg_isready -h 127.0.0.1
docker exec clab-gis-db su - postgres -c 'psql -tAc "select version();"'
```

Ожидаемо: `127.0.0.1:5432 - accepting connections` и строка версии PostgreSQL 16.

## 5. Сервисы ДМЗ

### web — nginx (10.10.10.11)

```sh
docker exec clab-gis-web curl -s http://127.0.0.1/ | grep -o 'Веб-сервер ГИС'
# из внешней сети через fw1 (публикация web:80)
docker exec clab-gis-ext-host curl -s -o /dev/null -w '%{http_code}\n' http://10.10.10.11/   # 200
# DMZ -> WAN через NAT на fw1
docker exec clab-gis-web curl -s http://198.51.100.80/ | grep -o 'Внешний сайт'
```

### ext-web — имитация внешнего сайта (198.51.100.80)

```sh
docker exec clab-gis-ext-host curl -s http://198.51.100.80/news/2026 | grep -o 'Внешний сайт'
```

### ftp — vsftpd (10.10.10.12)

```sh
docker exec clab-gis-dns curl -s ftp://10.10.10.12/pub/readme.txt --user ftpuser:ftppass
```

### eml — почта Postfix + Dovecot (10.10.10.13)

```sh
# SMTP
docker exec clab-gis-dns sh -c 'printf "EHLO test\r\nQUIT\r\n" | nc -w3 10.10.10.13 25'
# порты 25 (SMTP) и 143 (IMAP) слушают
docker exec clab-gis-eml sh -c 'ss -lntp | grep -E ":25|:143"'
```
## 6. RADIUS (FreeRADIUS + LDAP FreeIPA)

```sh
# проверка на самом RADIUS-сервере
docker exec clab-gis-radius bash -c \
  'echo "User-Name=testuser,User-Password=UserPass123" | radclient -x -t3 -r1 127.0.0.1:1812 auth testing123' \
  | grep -E 'Access-Accept|Access-Reject'

# проверка из внутренней сети (от имени captive-портала)
docker exec clab-gis-portal bash -c \
  'echo "User-Name=testuser,User-Password=UserPass123" | radclient -t3 -r1 10.10.10.15:1812 auth testing123' \
  | grep -E 'Access-Accept|Access-Reject'
```

Ожидаемо: `Received Access-Accept` — аутентификация по LDAP-каталогу FreeIPA.

---

## 7. Авторизация АРМ в интернете через captive-портал

Узел `portal` (10.10.20.2) — шлюз АРМ. До авторизации HTTP перехватывается,
после успешного RADIUS-входа IP попадает в `nftables`-набор `authorized`.

```sh
# 1) до входа: любой внешний сайт перехватывается -> страница входа
docker exec clab-gis-arm curl -s -H 'Accept: text/html' http://example.com/ | grep -o 'Captive Portal ГИС'

# 2) вход под доменной учёткой -> 302 на исходный URL
docker exec clab-gis-arm curl -s -i -d 'username=testuser&password=UserPass123' \
  http://example.com/login | grep -i '^Location'      # -> http://example.com/

# 3) IP АРМ появился в наборе авторизованных
docker exec clab-gis-portal nft list set inet gis_portal authorized

# 4) теперь реально открывается внешний сайт
docker exec clab-gis-arm curl -s http://example.com/ | grep -o 'Внешний сайт'

# 5) выход (чтобы повторить демонстрацию)
docker exec clab-gis-arm curl -s http://10.10.20.2/logout
docker exec clab-gis-portal nft list set inet gis_portal authorized   # снова пусто
```

Ожидаемо: до входа — страница «Captive Portal ГИС»; после входа в наборе
`authorized` появляется `10.10.20.12 timeout 1h`; открывается `ext-web`;
после `/logout` набор пуст.

---

## 8. VPN для удалённого пользователя (OpenVPN + RADIUS/LDAP)

Сервер — узел `vpn` (10.10.10.14:1194/udp); клиент получает адрес из пула
`10.8.0.0/24` и доступ во **внутреннюю** сеть.

```sh
# сервер слушает
docker exec clab-gis-vpn sh -c 'ss -lunp | grep 1194'

# подключение клиента с внешнего узла (учётка testuser/UserPass123)
docker exec clab-gis-ext-host bash -c '
  openvpn --config /etc/openvpn/client/client.ovpn --daemon --log /tmp/ovpn.log
  sleep 12
  ip -br addr show tun0
  ping -c2 10.10.20.10'

# журнал аутентификации на VPN (в нём виден Access-Accept от RADIUS)
docker exec clab-gis-vpn tail -5 /var/log/ovpn-auth.log
```

Ожидаемо: интерфейс `tun0 10.8.0.2/24`, пинг до FreeIPA `10.10.20.10` проходит,
в логе — `Access-Accept`.

Альтернативно — демонстрация «клиента» прямо с хоста (CLI, foreground):

```sh
sh scripts/vpn-client.sh          # openvpn в отдельном контейнере на ext-host
```

Отключить туннель с ext-host:

```sh
docker exec clab-gis-ext-host pkill -x openvpn
```

## 9. IDS (Suricata) — пассивный сенсор ДМЗ

Трафик портов ДМЗ зеркалируется на сенсор (`dmz-sw`, `tc mirred`).

```sh
# процесс сенсора
docker exec clab-gis-ids ps -e -o comm | grep -i suricata     # Suricata-Main

# сгенерировать событие: HTTP к сервису ДМЗ из внешней сети
docker exec clab-gis-ext-host curl -s -o /dev/null http://10.10.10.11/
sleep 3
docker exec clab-gis-ids tail -3 /var/log/suricata/fast.log
```

Ожидаемо в `fast.log`:

```
[1:1000001:1] GIS: HTTP к сервису ДМЗ из внешней сети ... 198.51.100.10:... -> 10.10.10.11:80
```

---

## 10. Логирование узлов (МЭ, IDS, VPN, IPA)

```sh
# МЭ: события firewall (nft log group -> ulogd -> /var/log/nft.log)
docker exec clab-gis-attacker ping -c2 10.10.20.10          # блокируется и логируется
docker exec clab-gis-fw1 tail -3 /var/log/nft.log

docker exec clab-gis-web ping -c2 10.10.20.12               # DMZ->LAN блокируется
docker exec clab-gis-fw2 tail -3 /var/log/nft.log
```
## 11. АРМ и внешний пользователь (GUI, noVNC)

### АРМ в домене

```sh
docker exec clab-gis-arm id testuser                 # uid=83400004(testuser)
docker exec clab-gis-arm sh -c 'ss -lntp | grep 6080'
```

Браузер: <http://172.20.20.100:6080/vnc.html> — Firefox сразу открывает
`http://example.com/` → страница портала → вход `testuser` / `UserPass123`
→ открывается внешний сайт.

### Внешний пользователь (VPN)

```sh
docker exec clab-gis-ext-host sh -c 'ss -lntp | grep 6080'
```

Браузер: <http://172.20.20.101:6080/vnc.html> → xterm → команда `vpn-up`.

---

## 12. Атакующий (внешний узел)

```sh
docker exec clab-gis-attacker ping -c2 10.10.10.11     # web в ДМЗ достижим извне (80)
docker exec clab-gis-attacker curl -s -o /dev/null -w '%{http_code}\n' http://10.10.10.11/   # 200
docker exec clab-gis-attacker ping -c2 10.10.20.10     # внутренняя сеть НЕдостижима (drop)
```

Ожидаемо: внешний доступ только к опубликованным сервисам (`web:80/443`,
`vpn:1194/udp`); попытка во внутреннюю сеть отбрасывается и логируется.

**Учётные данные стенда**

| Что | Логин | Пароль |
|-----|-------|--------|
| FreeIPA admin | `admin` | `Secret123` |
| Доменный пользователь (портал/VPN/АРМ) | `testuser` | `UserPass123` |
| RADIUS-клиент (secret) | — | `testing123` |
| FTP | `ftpuser` | `ftppass` |
| Почта | `mailuser` | `mailpass` |

**Узлы:**

| Узел        | Образ             | Сегмент     | Data IP                         | mgmt            | Роль |
|-------------|-------------------|-------------|---------------------------------|-----------------|------|
| `ext-sw`    | gis/linux         | —           | — (держатель бриджа)            | —               | коммутатор внешней сети |
| `dmz-sw`    | gis/linux         | —           | — (держатель бриджа)            | —               | коммутатор ДМЗ + SPAN для IDS |
| `lan-sw`    | gis/linux         | —           | — (держатель бриджа)            | —               | коммутатор внутренней сети |
| `fw1`       | gis/linux         | edge/ДМЗ    | `198.51.100.1`, `10.10.10.1`    | —               | внешний МЭ |
| `fw2`       | gis/linux         | ДМЗ/LAN     | `10.10.10.2`, `10.10.20.1`      | —               | внутренний МЭ |
| `ext-host`  | gis/arm           | внешняя     | `198.51.100.10`                 | `172.20.20.101` | удалённый пользователь (GUI + OpenVPN) |
| `attacker`  | gis/linux         | внешняя     | `198.51.100.100`                | —               | атакующий |
| `ext-dns`   | gis/dns           | внешняя     | `198.51.100.53`                 | —               | имитация DNS интернета |
| `ext-web`   | gis/web           | внешняя     | `198.51.100.80`                 | —               | имитация внешнего сайта |
| `dns`       | gis/dns           | ДМЗ         | `10.10.10.10`                   | —               | резолвер стенда |
| `web`       | gis/web           | ДМЗ         | `10.10.10.11`                   | —               | WEB (nginx) |
| `ftp`       | gis/ftp           | ДМЗ         | `10.10.10.12`                   | —               | FTP (vsftpd) |
| `eml`       | gis/eml           | ДМЗ         | `10.10.10.13`                   | —               | почта (postfix+dovecot) |
| `vpn`       | gis/vpn           | ДМЗ         | `10.10.10.14`                   | —               | VPN (OpenVPN + RADIUS) |
| `radius`    | gis/freeradius    | ДМЗ         | `10.10.10.15`                   | —               | RADIUS (LDAP FreeIPA) |
| `ids`       | gis/ids           | ДМЗ         | пассивный сенсор (без IP)       | —               | IDS (Suricata) |
| `portal`    | gis/portal        | внутренняя  | `10.10.20.2`                    | —               | captive-портал (NAS) |
| `arm`       | gis/arm           | внутренняя  | `10.10.20.12`                   | `172.20.20.100` | АРМ (GUI) |
| `ipa`       | gis/ipa           | внутренняя  | `10.10.20.10`                   | —               | DC — FreeIPA (Kerberos/LDAP/DNS) |
| `db`        | gis/postgres      | внутренняя  | `10.10.20.11`                   | —               | БД (postgres) |
