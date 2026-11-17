# Функции для показа МОЗ. Подключить один раз в терминале из папки GIS:
#   source ./demo_funcs.sh
# Дальше запускать короткие команды: topo, scan_ext, scan_ext_int, scan_dmz, scan_lan,
# nikto_web, falsepos, proof_src, matrix, szi. Файл только читает, стенд не меняет.

r() { n=$1; shift; docker run --rm --network container:clab-gis-$n --cap-add NET_RAW gis-scan "$@"; }

t() { s=$1; d=$2; p=$3; printf '%s -> %s:%s ' "$s" "$d" "$p"; docker run --rm --network container:clab-gis-$s gis-scan bash -c "timeout 3 bash -c 'exec 3<>/dev/tcp/$d/$p' 2>/dev/null && echo OPEN || echo closed"; }

topo() {
  for n in attacker ext-web fw1 web dns ftp eml vpn radius fw2 ipa db arm portal; do
    printf '%-9s' "$n"
    docker exec clab-gis-$n sh -c 'ip -br -4 a | grep -v "^lo" | awk "{printf \"%s \", \$3}"'
    echo
  done
}

scan_ext() {
  r attacker nmap -Pn -n -sS -sV -p- --min-rate 3000 --open 198.51.100.10 198.51.100.53 198.51.100.80 10.10.10.11 | grep -vE '^(SF|1 service unrecognized)'
}

scan_ext_int() {
  r attacker nmap -Pn -n -sS -p 21,22,25,53,80,88,143,389,443,636,5432,5900,6080,8443 10.10.10.10-15 10.10.20.10-12
}

scan_dmz() {
  r dns nmap -Pn -n -sS -sV -p 21,25,53,80,143,389,636,5432,5900,8443 10.10.10.11-13 10.10.20.10-12
}

scan_lan() {
  r arm nmap -Pn -n -sS -p 21,25,53,80,143,389,443,636,5432 10.10.10.12 10.10.10.13 10.10.20.10 10.10.20.11
}

proof_src() {
  r attacker nmap -Pn -n -sS -p80 10.10.10.11
}

nikto_web() {
  r attacker perl /opt/nikto/program/nikto.pl -h http://10.10.10.11 -ask no | cut -c1-120
}

falsepos() {
  for p in /.htpasswd /.bash_history /JAMonAdmin.jsp /nonexistent_xyz; do
    printf '%s ' "$p"
    r attacker curl -s -o /dev/null -w '%{http_code} %{size_download}\n' "http://198.51.100.80$p"
  done
}

matrix() {
  t attacker 10.10.10.11 80
  t attacker 10.10.20.11 5432
  t dns 10.10.20.10 389
  t dns 10.10.20.11 5432
  t vpn 10.10.20.11 5432
  t vpn 10.10.20.10 8443
  t arm 10.10.20.11 5432
}

szi() {
  for n in arm db ipa web ftp eml; do
    printf '%s: ' "$n"
    docker exec clab-gis-$n sh -c 'command -v clamscan freshclam auditd aide fail2ban-client || echo ничего-нет'
  done
}
