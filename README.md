# План показа преподавателю: всё вживую, по шагам

## Найденные недостатки: что, где и чем доказано

Критичность по трёхуровневой шкале, без завышения. Высоких нет. Номера совпадают с таблицей 5 отчёта. Номер шага это шаг ниже в этом файле.

Подтверждённые:

| № | Название | Смысл | Шаг | Доказательство |
|---|---|---|---|---|
| 1 | VPN даёт полный доступ в ЛВС (средняя) | клиент VPN попадает к БД и админке IPA без ограничения портов, вход по паролю без клиентского сертификата | 8, 13 | на fw2 строка `ip saddr 10.10.10.14 accept`; `t vpn 10.10.20.11 5432` и `t vpn 10.10.20.10 8443` дают OPEN; в `server.conf` `verify-client-cert none` |
| 2 | Анонимный LDAP на ipa (средняя) | без пароля читается список пользователей, доступно и из ДМЗ | 4, 6 | `Anonymous bind OK` в скане из dns; `ldapsearch -x` выводит `uid=admin`, `uid=radius`, `uid=testuser` |
| 3 | HBAC allow_all (средняя) | любой доменный пользователь входит на любой хост | 12 | `ipa hbacrule-find`: правило `allow_all`, категории all |
| 4 | Слабая парольная политика (средняя) | длина 8, сложность 0, история 0; локально пароли без срока | 11, 12 | `ipa pwpolicy-show`; `PASS_MAX_DAYS 99999` в `login.defs` |
| 5 | PostgreSQL открыт всем адресам (средняя) | пароль проверяется, но источник не ограничен, SSL выключен | 13 | в `pg_hba.conf` строка `host all all all scram-sha-256`; `t arm 10.10.20.11 5432` OPEN |
| 6 | Нет централизованного журналирования (средняя) | журналы только локально, при взломе узла их можно изменить | 10 | rsyslog и auditd на ipa, radius, web, db, arm отсутствуют |
| 7 | Нет СЗИ от НСД, антивируса, контроля целостности (средняя) | требуется для реальной ГИС | 14, 11 | `ничего-нет` на всех узлах |
| 8 | СОВ с 4 демо-правилами (низкая) | нет набора сигнатур и оповещений | 9 | `cat local.rules`; сработка только в `fast.log` |
| 9 | МЭ: input accept, нет drop invalid, исходящий трафик не ограничен (низкая) | сам МЭ не защищён на входе | 8 | `nft list ruleset`: `chain input ... policy accept` |
| 10 | Web без TLS и заголовков безопасности (низкая) | нет CSP, HSTS и др., раскрыта версия nginx | 7 | nikto: 5 пропущенных заголовков, `Server: nginx/1.31.8` |
| 11 | Почта и FTP: широкий mynetworks, VRFY, FTP без TLS, IMAP 143 без TLS (низкая) | ослабленная защита сервисов ДМЗ | 6 | `postconf -n`: `mynetworks = 127.0.0.0/8, 10.10.0.0/16, 172.20.20.0/24`; `vsftpd.conf`: `allow_writeable_chroot=YES` |
| 12 | Права 644 на файлы правил, eve.json без ротации (низкая) | правила и журналы читаются всеми | 11, 10 | `ls -la /etc/clab`; размер `eve.json` в `ls -la /var/log/suricata` |
| 13 | ext-host: VNC и noVNC с листингом каталога (низкая, особенность стенда) | открытые порты 5900 и 6080 снаружи | 2 | в скане 5900 vnc и 6080 noVNC; в отпечатке `Directory listing for /` |
| 14 | vsftpd 3.0.3: низкие CVE-2021-30047 и CVE-2021-3618 (низкая) | по версии, не проверялась эксплуатацией | 6 | `dpkg-query -W vsftpd` выводит `3.0.3-13+b2` |

Найденные, но опровергнутые (в отчёт как уязвимости не включены):

| № | Что показалось | Найдено (шаг) | Опровергнуто (шаг) | Чем опровергнуто |
|---|---|---|---|---|
| А | nikto: на ext-web доступны `.htpasswd`, `.bash_history`, `JAMonAdmin.jsp` | 7 (nikto по ext-web) | 7 (curl по тем же путям) | на любой путь, даже `/nonexistent_xyz`, ответ `200 1359`: сервер отвечает одной страницей |
| Б | nmap: Postfix «open relay 16/16» | 6 (`smtp-open-relay`) | 6 (`postconf`), 2 (порт 25 снаружи) | релей только для сети `mynetworks`; с attacker порт 25 `filtered` |
| В | Unbound 1.17.1 уязвим к KeyTrap (CVE-2023-50387) | 6 (версия 1.17.1) | 6 (полная версия пакета) | пакет `1.17.1-2+deb12u4` включает исправление Debian |
| Г | FTP допускает анонимный вход | 4 (открыт порт 21) | 6 (`ftp-anon`, `vsftpd.conf`) | `ftp-anon` пуст, `anonymous_enable=NO` |
| Д | Порт 80 открыт на ftp и eml из ЛВС | 5 (скан с arm) | 5 (`curl -sI`) | ответ `Server: GISPortal`: HTTP перехватывает captive-портал |

Формат каждого шага: команда, что видим, что сказать. Готовые файлы из `scans/` не показываем, всё запускается на глазах. Все команды только читают, стенд не меняют (кроме шага 0: остановка и запуск).

Правила для терминала (zsh):
- В блоки кода комментарии не вставляем: в интерактивном zsh `#` не комментарий и сломает команду. Копировать блок целиком.
- Два окна терминала: окно 1 основное, окно 2 только для перехвата трафика (шаг 3).

Кто с какого узла работает. «Нужный узел» зависит от того, что проверяем:

| Что проверяем | Откуда идём | Узел | Адрес | Зачем этот узел |
|---|---|---|---|---|
| Внешний аудит | из внешней сети | attacker | 198.51.100.100 | имитация нарушителя в интернете |
| Срез ДМЗ | из ДМЗ | dns | 10.10.10.10 | узел ДМЗ, который МЭ2 пускает в LDAP на ipa |
| Срез ЛВС | из внутренней сети | arm | 10.10.20.12 | АРМ пользователя в домене |
| Внутренний аудит | на самих узлах | arm, ipa, db, ... | разные | конфигурации читаем через docker exec |

Сканеры в узлах не установлены (в attacker только curl и nc). Сканер (nmap, nikto) запускается отдельным контейнером gis-scan в сетевом пространстве нужного узла (`--network container:clab-gis-<узел>`): у него тот же адрес, hostname и интерфейс, что у узла. Это доказываем в шаге 3.

## Шаг 0. Остановка и запуск стенда

Папка: `final_deploy/deploy`. Нужен sudo, пароль вводится вручную. Останавливать только так, не через `docker stop`.

Остановка:

```sh
cd final_deploy/deploy
time sh scripts/down.sh
docker ps -a --filter name=clab-gis
docker volume ls | grep -E 'ipa-data|vpn-data'
```

Что видим: список контейнеров пуст, тома `ipa-data` и `vpn-data` остались (в них каталог FreeIPA и PKI VPN).

Запуск:

```sh
time sh scripts/deploy.sh --skip-bootstrap
sh scripts/arm-join.sh
```

Что видим: образы пропускаются (`уже есть, пропуск`), containerlab создаёт 20 узлов, `arm-join.sh` вводит АРМ в домен и печатает `uid=1357000004(testuser)`. Время `time` засечь на репетиции, я его целиком не замерял.

Проверка после запуска:

```sh
docker ps --filter name=clab-gis --format '{{.Names}}' | wc -l
docker ps -a --filter name=clab-gis --filter status=exited
docker exec clab-gis-ipa ipactl status
docker exec clab-gis-arm id testuser
```

Что видим: `20`; пустой список остановленных; все службы IPA `RUNNING`; `uid=1357000004(testuser)`.

Что сказать: стенд описан кодом (topology.clab.yml, образы, скрипты) и поднимается одной командой. Данные IPA и ключи VPN в томах, поэтому повторный запуск занимает секунды, а не 5 минут первичной установки FreeIPA (замерено 5 мин 18 с).

Чего не делать: `docker stop` (повторный `deploy` не поднимет остановленные ipa и radius, ошибка `cannot be reconciled`) и удалять тома `ipa-data`, `vpn-data` перед показом.

Подготовка терминала для остальных шагов (один раз, в папке GIS):

```sh
cd ~/Study/Методы\ и\ средства\ защиты\ информации\ в\ объектах\ КИИ/GIS
r(){ n=$1; shift; docker run --rm --network container:clab-gis-$n --cap-add NET_RAW gis-scan "$@"; }
t(){ s=$1; d=$2; p=$3; printf '%s -> %s:%s ' $s $d $p; docker run --rm --network container:clab-gis-$s gis-scan bash -c "timeout 3 bash -c 'exec 3<>/dev/tcp/$d/$p' 2>/dev/null && echo OPEN || echo closed"; }
```

## Шаг 1. Топология

Команда:

```sh
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep clab-gis
```

Что видим: 20 узлов `clab-gis-*`, статус `Up`.

Команда:

```sh
for n in attacker ext-web fw1 web dns ftp eml vpn radius fw2 ipa db arm portal; do printf '%-9s' $n; docker exec clab-gis-$n sh -c 'ip -br -4 a | grep -v "^lo" | awk "{printf \"%s \", \$3}"'; echo; done
```

Что видим: адреса по сегментам.
- внешняя сеть 198.51.100.0/24: attacker .100, ext-web .80, fw1 .1 (внешняя сторона)
- ДМЗ 10.10.10.0/24: fw1 .1, fw2 .2, dns .10, web .11, ftp .12, eml .13, vpn .14 (и tun 10.8.0.1), radius .15
- ЛВС 10.10.20.0/24: fw2 .1, portal .2, ipa .10, db .11, arm .12 (и 172.20.20.100 управляющая сеть)

Что сказать: три сегмента, два МЭ (fw1 внешний, fw2 внутренний), сенсор СОВ ids без адреса (зеркало с dmz-sw), коммутаторы это Linux bridge. Схема на рисунке 1 отчёта.

## Шаг 2. Внешний аудит: порты и сервисы с узла attacker

Команда (кто мы):

```sh
docker exec clab-gis-attacker sh -c 'hostname; ip -br -4 a | grep -v "^lo"'
```

Что видим: `attacker` и `198.51.100.100/24`. Это позиция внешнего нарушителя.

Команда (внешний сегмент и опубликованный web, полный диапазон портов):

```sh
r attacker nmap -Pn -n -sS -sV -p- --min-rate 3000 --open 198.51.100.10 198.51.100.53 198.51.100.80 10.10.10.11
```
«nmap не узнал noVNC и показал отпечаток, но в нём видно листинг каталога на 6080

Что видим (идёт 1-2 минуты): ext-host 5900 (VNC) и 6080, ext-dns 53/tcp dnsmasq 2.90, ext-web 80 nginx 1.31.8, web 10.10.10.11 порт 80 nginx 1.31.8. У узлов внешнего сегмента есть `MAC Address`, у web его нет, потому что он за МЭ1 и трафик маршрутизируется.



Команда (внутренние адреса снаружи):

```sh
r attacker nmap -Pn -n -sS -p 21,22,25,53,80,88,143,389,443,636,5432,5900,6080,8443 10.10.10.10-15 10.10.20.10-12
```

Что видим (около 10 секунд): везде `filtered`, кроме 10.10.10.11 порт 80 `open`. `Host is up` не значит, что узел отвечает: при `-Pn` nmap считает хосты живыми без проверки.

Что сказать: снаружи видна только публикация web:80 и внешний сегмент, внутренняя сеть закрыта политикой forward=drop на МЭ1.

## Шаг 3. Доказательство, что скан идёт именно с attacker

Окно 2:

```sh
docker exec clab-gis-fw1 tcpdump -l -ni eth1 -c 1 'tcp[tcpflags]==tcp-syn and dst host 10.10.10.11 and dst port 80'
```

Окно 1:

```sh
r attacker nmap -Pn -n -sS -p80 10.10.10.11
```

Что видим в окне 2: `IP 198.51.100.100.<порт> > 10.10.10.11.80: Flags [S]`. Источник 198.51.100.100, то есть attacker, а не ноутбук.

Дополнительно, что сканер делит сетевой стек с узлом:

атакер
```sh
r attacker sh -c 'hostname; ip -br -4 a | grep -v "^lo"'
```

узел гис
```
docker exec clab-gis-attacker sh -c 'hostname; ip -br -4 a | grep -v "^lo"'
```
Он совпадает с выводом r attacker ...: тот же интерфейс eth1@if42 и тот же адрес 198.51.100.100/24. Это подтверждает, что сканер работает в том же сетевом окружении, что и узел attacker
Что видим: `attacker` и `198.51.100.100/24`, как при заходе в сам узел.

## Шаг 4. Срез из ДМЗ с узла dns

Команда:

```sh
docker exec clab-gis-dns sh -c 'hostname; ip -br -4 a | grep -v "^lo"'
```

Что видим: `dns`, `10.10.10.10/24`.

Команда:

```sh
r dns nmap -Pn -n -sS -sV -p 21,25,53,80,143,389,636,5432,5900,8443 10.10.10.11-13 10.10.20.10-12
```

Что видим (около 25 секунд): web 80 nginx; ftp 21 vsftpd 3.0.3; eml 25 Postfix и 143 Dovecot; ipa открыты только 53, 389 и 636 (`Anonymous bind OK`); db 10.10.20.11 и arm 10.10.20.12 закрыты (5432, 5900, 8443 не видны).

Что сказать: МЭ2 пускает из ДМЗ в ЛВС только DNS, LDAP и LDAPS на ipa. Остальное режется.

## Шаг 5. Срез из ЛВС с узла arm

Команда:

```sh
docker exec clab-gis-arm sh -c 'hostname; ip -br -4 a | grep -v "^lo"'
```

Что видим: `arm.otlichnik.lab`, `10.10.20.12/24` (и управляющий адрес 172.20.20.100).

Команда:

```sh
r arm nmap -Pn -n -sS -p 21,25,53,80,143,389,443,636,5432 10.10.10.12 10.10.10.13 10.10.20.10 10.10.20.11
```

Что видим (около 4 секунд): ipa открыты 53, 80, 389, 443, 636; db 5432 открыт; у ftp и eml 21, 25, 143 не видны, но порт 80 отвечает.

Команда (проверка, кто отвечает на порт 80 у ftp):

```sh
r arm curl -sI http://10.10.10.12/
```

Что видим: `HTTP/1.0 501 Unsupported method ('HEAD')` и `Server: GISPortal`. На ftp нет веб-сервера, отвечает портал.

Что сказать: порт 80 на ftp и eml отвечает не самим сервисом, а captive-порталом GISPortal, который перехватывает HTTP из ЛВС до авторизации. Это не уязвимость (опровергнутая находка Д).

## Шаг 6. Уязвимости сервисов

Команда:

```sh
docker exec clab-gis-dns dpkg-query -W unbound
docker exec clab-gis-ftp dpkg-query -W vsftpd
docker exec clab-gis-eml dpkg-query -W dovecot-core postfix
docker exec clab-gis-web nginx -v
docker exec clab-gis-vpn dpkg-query -W openvpn
docker exec clab-gis-db dpkg-query -W postgresql-16
```

Что видим: unbound 1.17.1-2+deb12u4, vsftpd 3.0.3-13+b2, dovecot 2.3.19.1 deb12u7, postfix 3.7.11, nginx 1.31.8, openvpn 2.6.14, postgresql 16.16.

Что сказать: у сканера нет интернета, онлайн-баз нет, версии сопоставляли вручную. В Unbound исправления KeyTrap уже внутри (deb12u2 и выше), поэтому уязвимости нет. У vsftpd только низкие CVE-2021-30047 и CVE-2021-3618. Критичных нет, основные проблемы в конфигурации.

Команда (анонимный LDAP, главная конфигурационная находка):

```sh
docker exec clab-gis-ipa ldapsearch -x -LLL -H ldap://localhost -b cn=users,cn=accounts,dc=otlichnik,dc=lab uid
r dns nmap -Pn -n -p389 --script ldap-rootdse 10.10.20.10
```

Что видим: без пароля выводятся `uid=admin`, `uid=radius`, `uid=testuser`; nmap показывает namingContexts (`dc=otlichnik,dc=lab`, `cn=changelog`, `o=ipaca`) из ДМЗ.

Команда (FTP и почта):

```sh
r dns nmap -Pn -n -p21 --script ftp-anon 10.10.10.12
docker exec clab-gis-ftp grep -E 'anonymous_enable|write_enable|allow_writeable_chroot' /etc/vsftpd.conf
docker exec clab-gis-eml postconf -n | grep -E 'mynetworks|smtpd_relay_restrictions|smtpd_tls_security'
r dns nmap -Pn -n -p25 --script smtp-open-relay 10.10.10.13
```

Что видим: у ftp-anon нет строки с результатом (анонимный вход не разрешён), `anonymous_enable=NO`, `write_enable=YES`, `allow_writeable_chroot=YES`; у Postfix `mynetworks = 127.0.0.0/8, 10.10.0.0/16, 172.20.20.0/24`, TLS `may`; nmap пишет `open relay (16/16 tests)`.

Что сказать: nmap ошибается в трактовке. Релей разрешён только клиентам из `mynetworks`, снаружи порт 25 закрыт. Реальное замечание: слишком широкий mynetworks.

## Шаг 7. Веб

Команда:

```sh
r attacker perl /opt/nikto/program/nikto.pl -h http://10.10.10.11 -ask no | cut -c1-120
```

Что видим (несколько секунд): `Server: nginx/1.31.8`, предупреждения об отсутствии заголовков permissions-policy, strict-transport-security, x-content-type-options, content-security-policy, referrer-policy. Ключ `-ask no` отключает вопрос nikto про отправку версии разработчикам (проверено по `nikto.pl -Help`), иначе скрипт ждёт ответа `y/n`.

Команда (тот же сканер по внешнему сайту):

```sh
r attacker perl /opt/nikto/program/nikto.pl -h http://198.51.100.80 -ask no | cut -c1-120
```

Что видим: кроме тех же заголовков сканер сообщает `/.htpasswd: Contains authorization information`, `/.bash_history`, `/.sh_history`, `/JAMonAdmin.jsp`. Выглядит как серьёзная находка, проверяем следующей командой.

Команда:

```sh
for p in /.htpasswd /.bash_history /JAMonAdmin.jsp /nonexistent_xyz; do printf '%s ' $p; r attacker curl -s -o /dev/null -w '%{http_code} %{size_download}\n' http://198.51.100.80$p; done
```

Что видим: везде `200 1359`, включая заведомо несуществующий путь. Значит находки nikto по ext-web (`.htpasswd` и др.) ложные.

Что сказать: реальные замечания по web: нет TLS и заголовков безопасности, раскрыта версия nginx.

## Шаг 8. Межсетевые экраны

Команда:

```sh
docker exec clab-gis-fw1 nft list ruleset
docker exec clab-gis-fw2 nft list ruleset
```

Что видим и показать пальцем:
- fw1: `policy drop` в forward, `ct state established,related accept`, наружу разрешены только `10.10.10.11` tcp 80 и 443 и `10.10.10.14` udp 1194, логирование `fw1-fwd-drop`, `masquerade` в nat; `input` с политикой `accept`.
- fw2: DMZ to LAN только ipa udp 53 и tcp 53, 389, 636; строка `ip saddr 10.10.10.14 accept` (весь трафик VPN-узла в ЛВС без ограничения портов).

Живая проверка блокировки и записи в журнал:

```sh
r attacker bash -c 'timeout 3 bash -c "exec 3<>/dev/tcp/10.10.20.11/5432" && echo OPEN || echo blocked'
docker exec clab-gis-fw1 tail -2 /var/log/nft.log | cut -c1-200
```

Что видим: `blocked`, а в журнале fw1 свежие строки `fw1-fwd-drop IN=eth1 OUT=eth2 ... SRC=198.51.100.100 DST=10.10.20.11 ... PROTO=TCP`. Источник attacker, цель db, блокировка и запись в журнал подтверждены.

## Шаг 9. СОВ Suricata

Команда:

```sh
docker exec clab-gis-ids cat /etc/clab/local.rules
r attacker curl -s -o /dev/null -w 'web:%{http_code}\n' http://10.10.10.11/
docker exec clab-gis-ids tail -2 /var/log/suricata/fast.log
```

Что видим: 4 демонстрационных правила (HTTP, HTTPS, SSH, ICMP из внешней сети); `web:200`; в `fast.log` свежая строка `[1:1000001:1] GIS: HTTP к сервису ДМЗ из внешней сети {TCP} 198.51.100.100:<порт> -> 10.10.10.11:80`.

Что сказать: СОВ видит трафик через зеркало (SPAN) с dmz-sw. Минусы: правил всего 4, набора сигнатур (ET) нет, оповещений администратору и передачи в SIEM нет, `eve.json` без ротации.

## Шаг 10. Журналирование

Команда:

```sh
docker exec clab-gis-fw1 ls -la /var/log/nft.log
docker exec clab-gis-ids ls -la /var/log/suricata
for n in ipa radius web db arm; do printf "$n: "; docker exec clab-gis-$n sh -c 'ps aux | grep -c "[r]syslogd"; command -v auditd || echo auditd-нет' | tr '\n' ' '; echo; done
```

Что видим: `nft.log` и `fast.log`, `eve.json` лежат только локально (права 644); на ipa, radius, web, db, arm rsyslog не запущен (`0`), auditd нет.

Что сказать: удалённого сбора журналов нет, при компрометации узла журнал можно изменить.

## Шаг 11. Внутренний аудит узлов (passwd, shadow, sudoers, PAM)

Команда:

```sh
docker exec -i clab-gis-arm sh < scans/10_audit_script.sh
```

Что видим: скрипт (только чтение, хешей не печатает) выводит ОС, UID 0 (только root), локальные учётки (nova), параметры `login.defs` (`PASS_MAX_DAYS 99999`), `pam_pwquality`, sudoers (пусто), прослушиваемые порты, SUID-файлы, права на shadow (`640 root:shadow`), отсутствие антивируса и auditd.

Команда (по пунктам методички):

```sh
docker exec clab-gis-arm awk -F: '$3==0{print $1}' /etc/passwd
docker exec clab-gis-arm passwd -Sa
docker exec clab-gis-arm grep -E '^PASS_(MAX|MIN)_DAYS' /etc/login.defs
docker exec clab-gis-arm grep -R pwquality /etc/pam.d
docker exec clab-gis-fw1 ls -la /etc/clab
```

Что видим: `root`; статусы учёток без хешей; `99999` и `0`; `pam_pwquality.so retry=3` только на arm, ipa, ids; файлы правил МЭ в `/etc/clab` с правами 644.

Что сказать: LinPEAS не запускали: интернета в контейнерах нет, скачанный вслепую скрипт не выполняем. Заменён собственным read-only скриптом. Файл shadow не читали, только `passwd -S`.

## Шаг 12. Доменные политики FreeIPA

Команда:

```sh
docker exec clab-gis-ipa sh -c 'echo "$PASSWORD" | kinit admin'
docker exec clab-gis-ipa ipa pwpolicy-show
docker exec clab-gis-ipa ipa krbtpolicy-show
docker exec clab-gis-ipa ipa hbacrule-find
docker exec clab-gis-ipa ipa sudorule-find
docker exec clab-gis-ipa ipa user-find
```

Что видим: пароль берётся из переменной контейнера, в команде его нет. Политика: срок 90 дней, длина 8, классов символов 0, история 0, блокировка после 6 неудач на 600 с; Kerberos 24 часа и продление 7 суток; HBAC `allow_all` для всех пользователей и хостов; sudo-правил 0; пользователи admin, radius, testuser.

Что сказать: любой доменный пользователь может войти на любой хост, парольная политика слабая. Это находки 3 и 4 таблицы 5 отчёта.

## Шаг 13. Матрица доступа и VPN

Команда:

```sh
t attacker 10.10.10.11 80
t attacker 10.10.20.11 5432
t dns 10.10.20.10 389
t dns 10.10.20.11 5432
t vpn 10.10.20.11 5432
t vpn 10.10.20.10 8443
t arm 10.10.20.11 5432
```

Что видим: `OPEN` у attacker к web:80, dns к ipa:389, vpn к db:5432 и ipa:8443, arm к db:5432; `closed` у attacker к db:5432 и dns к db:5432.

Команда:

```sh
docker exec clab-gis-vpn grep -Ev '^\s*(#|;|$)' /etc/openvpn/server.conf
docker exec clab-gis-db sh -c 'grep -Ev "^\s*(#|$)" $(find /etc/postgresql /var/lib/postgresql -name pg_hba.conf | head -1)'
```

Что видим: в OpenVPN `verify-client-cert none`, `duplicate-cn`, нет `tls-crypt`; в `pg_hba.conf` строка `host all all all scram-sha-256`.

Что сказать: главная находка. VPN-клиент получает прямой доступ к PostgreSQL и административному интерфейсу IPA, потому что fw2 пускает весь трафик vpn в ЛВС, а на самом VPN нет клиентского сертификата.

## Шаг 14. СЗИ и антивирус

Команда:

```sh
for n in arm db ipa web ftp eml; do printf "$n: "; docker exec clab-gis-$n sh -c 'command -v clamscan freshclam auditd aide fail2ban-client || echo ничего-нет'; done
```

Что видим: `ничего-нет` на всех узлах.

Что сказать: СЗИ от НСД, антивируса, контроля целостности и контроля устройств нет, мандатного доступа нет (не Astra). Для учебного стенда это ожидаемо, для рабочей ГИС в рекомендациях.

## Шаг 15. Итог

Открыть `Отчет_МОЗ_стенд_ГИС_1.docx`, таблица 5: 13 находок, 7 средних, 6 низких, у каждой рекомендация. Стенд в ходе работы не менялся, исправление это задание 2.

Вероятные вопросы:
- Почему не OpenVAS или Nessus: нет интернета в стенде и лицензий, использовали nmap NSE и nikto, версии сопоставляли вручную.
- Почему нет LinPEAS: скачанный код без просмотра не запускаем, интернета нет, заменён своим скриптом.
- Почему критичных нет: не преувеличивали, внешний периметр закрыт, основные риски во внутренних политиках.
- Почему open relay не уязвимость: проверили `mynetworks`, снаружи порт 25 закрыт, это особенность выдачи NSE.
- Как быстро поднимается стенд: после `down.sh` и `deploy.sh --skip-bootstrap` секунды, службы IPA около 20 секунд; первичная установка FreeIPA на пустом томе около 5 минут.
