#!/usr/bin/env python3
# Captive-портал: страница входа + проверка через RADIUS (radclient) ->
# при Access-Accept IP клиента попадает в nftables-набор authorized.
#
# Логика captive-портала:
#   * nftables перехватывает HTTP неавторизованного клиента и перенаправляет
#     его на этот портал (см. nftables.conf, chain prerouting);
#   * портал запоминает исходный URL (Host + path) по IP клиента и отдаёт
#     страницу входа;
#   * после успешной проверки RADIUS IP попадает в набор authorized, а браузер
#     получает 302 на тот же исходный URL — открывается настоящий внешний сайт.
import html
import http.server
import os
import re
import subprocess
import threading
import time
import urllib.parse

RADIUS = os.environ.get("RADIUS_SERVER", "10.10.10.15")
SECRET = os.environ.get("RADIUS_SECRET", "testing123")
PORTAL_IP = os.environ.get("PORTAL_IP", "10.10.20.2")
TIMEOUT = os.environ.get("SESSION_TIMEOUT", "3600s")
NFT_TABLE = os.environ.get("NFT_TABLE", "inet gis_portal")
NFT_SET = os.environ.get("NFT_SET", "authorized")
PORT = int(os.environ.get("PORTAL_PORT", "80"))

# Куда отправить браузер, если исходный сайт не был запомнен (например,
# пользователь открыл портал по прямому IP, а не через внешний сайт).
DEFAULT_REDIRECT = os.environ.get("DEFAULT_REDIRECT", "http://198.51.100.80/")

# Сколько секунд помнить исходный URL. Сессия RADIUS живёт дольше, но
# страницу входа обычно заполняют сразу.
PENDING_TTL = int(os.environ.get("PENDING_TTL", "1800"))

# Служебные URL, которыми ОС/браузер проверяют наличие captive-портала.
# На них отвечаем редиректом на портал, а не страницей (так детект надёжнее).
PROBE_PATHS = {
    "/generate_204",
    "/gen_204",
    "/success.txt",
    "/connecttest.txt",
    "/ncsi.txt",
    "/check_network_status.txt",
    "/hotspot-detect.html",
    "/library/test/success.html",
    "/canonical.html",
}

# Host: имя/IP с необязательным портом. Нужен, чтобы не подставить в
# Location произвольную строку из заголовка (в т.ч. с CR/LF).
HOST_RE = re.compile(
    r"^(?:"
    r"[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?"
    r"|\[[0-9A-Fa-f:.]+\]"
    r")(?::\d{1,5})?$"
)

# ip клиента -> (время запоминания, исходный URL)
_pending = {}
_pending_lock = threading.Lock()


def page(title, body):
    return ("<!doctype html><html lang='ru'><head><meta charset='utf-8'>"
            "<meta name='viewport' content='width=device-width, initial-scale=1'>"
            f"<title>{html.escape(title)}</title></head><body>"
            f"<h2>{html.escape(title)}</h2>{body}</body></html>")


FORM = (
    "<p>Для доступа в интернет войдите под доменной учёткой (FreeIPA).</p>"
    "<p>После входа откроется сайт, который вы запрашивали.</p>"
    "<form method='post' action='/login'>"
    "Логин: <input name='username' autocomplete='username'><br><br>"
    "Пароль: <input name='password' type='password' "
    "autocomplete='current-password'><br><br>"
    "<button type='submit'>Войти</button></form>"
)


def host_only(host):
    """Возвращает хост без порта (для сравнения с адресом портала)."""
    host = host.strip()
    if host.startswith("[") and "]" in host:
        return host[1:host.index("]")].lower()
    if host.count(":") == 1:
        return host.rsplit(":", 1)[0].lower()
    return host.lower().rstrip(".")


def is_portal_host(host):
    return host_only(host) in {
        PORTAL_IP.lower(),
        "portal",
        "portal.otlichnik.lab",
        "localhost",
        "127.0.0.1",
        "::1",
    }


def remember(ip, url):
    """Запоминает, какой сайт открывал клиент до авторизации."""
    now = time.time()
    with _pending_lock:
        _pending[ip] = (now, url)
        for key, (ts, _) in list(_pending.items()):
            if now - ts > PENDING_TTL:
                _pending.pop(key, None)
        if len(_pending) > 4096:
            oldest = min(_pending, key=lambda k: _pending[k][0])
            _pending.pop(oldest, None)


def take(ip):
    """Забирает запомненный URL (однократно)."""
    now = time.time()
    with _pending_lock:
        item = _pending.pop(ip, None)
    if not item:
        return None
    ts, url = item
    return url if now - ts <= PENDING_TTL else None


def radius_check(user, password):
    # radclient строит атрибуты из строки: перевод строки позволил бы
    # подмешать лишние атрибуты, поэтому такие данные не принимаем.
    if any(c in user + password for c in "\r\n"):
        return False, "недопустимые символы в учётных данных"
    req = f"User-Name={user},User-Password={password}"
    try:
        out = subprocess.run(
            ["radclient", "-x", "-t", "3", "-r", "1",
             f"{RADIUS}:1812", "auth", SECRET],
            input=req.encode(), stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, timeout=10).stdout.decode()
    except Exception as e:  # noqa: BLE001
        return False, str(e)
    return ("Access-Accept" in out), out


def _nft(*args):
    return subprocess.run(
        ["nft", *args], stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, check=False).returncode


def authorize(ip):
    # Повторный вход должен обновлять таймаут сессии, поэтому элемент
    # сначала удаляем (если его нет — nft просто вернёт ошибку, игнорируем).
    _nft("delete", "element", NFT_TABLE, NFT_SET, "{", ip, "}")
    rc = _nft("add", "element", NFT_TABLE, NFT_SET,
              "{", ip, "timeout", TIMEOUT, "}")
    return rc == 0


def deauthorize(ip):
    _nft("delete", "element", NFT_TABLE, NFT_SET, "{", ip, "}")


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "GISPortal"
    sys_version = ""

    def version_string(self):
        return self.server_version

    # ---- ответы ---------------------------------------------------------
    def _send(self, code, body, extra_headers=None):
        data = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        # Страницу входа нельзя кешировать: иначе браузер может показать её
        # даже после успешной авторизации.
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        self.send_header("Connection", "close")
        for name, value in (extra_headers or {}).items():
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(data)

    def _redirect(self, url, code=302):
        self.send_response(code)
        self.send_header("Location", url)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", "0")
        self.send_header("Connection", "close")
        self.end_headers()

    # ---- вспомогательное ------------------------------------------------
    def _original_url(self):
        """URL, который клиент пытался открыть (до перехвата nftables)."""
        host = (self.headers.get("Host") or "").strip()
        if not host or not HOST_RE.match(host) or is_portal_host(host):
            return None
        path = self.path if self.path.startswith("/") else "/" + self.path
        return f"http://{host}{path}"

    def _client_ip(self):
        return self.client_address[0]

    # ---- HTTP -----------------------------------------------------------
    def do_GET(self):
        path = urllib.parse.urlsplit(self.path).path
        ip = self._client_ip()

        if path == "/logout":
            deauthorize(ip)
            print(f"[portal] LOGOUT {ip}", flush=True)
            self._send(200, page(
                "Выход выполнен",
                f"<p>IP {html.escape(ip)} удалён из списка авторизованных.</p>"
                "<p><a href='/'>Вернуться на портал</a></p>"))
            return

        # Проверки captive-portal detection: отправляем браузер на портал.
        if path in PROBE_PATHS:
            self._redirect(f"http://{PORTAL_IP}/")
            return

        # Иконку/robots не считаем «исходным сайтом».
        if path in ("/favicon.ico", "/robots.txt"):
            self.send_response(204)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return

        target = self._original_url()
        accept = self.headers.get("Accept", "")
        # Навигацию браузера отличаем от фоновых запросов (пробы ОС,
        # картинки и т.п.): у перехода по ссылке Accept содержит text/html.
        if target and "text/html" in accept:
            remember(ip, target)
            print(f"[portal] INTERCEPT {ip} -> {target}", flush=True)

        self._send(200, page("Captive Portal ГИС", FORM))

    def do_POST(self):
        path = urllib.parse.urlsplit(self.path).path
        if path != "/login":
            self._send(404, page("Не найдено",
                                 "<p>Запрошенная страница отсутствует.</p>"))
            return

        try:
            length = int(self.headers.get("Content-Length", "0") or 0)
        except ValueError:
            length = 0
        if length > 8192:
            self._send(413, page("Слишком большой запрос",
                                 "<p>Данные формы превышают допустимый размер.</p>"))
            return

        data = self.rfile.read(length).decode("utf-8", "replace")
        q = urllib.parse.parse_qs(data)
        user = q.get("username", [""])[0].strip()
        pw = q.get("password", [""])[0]
        ip = self._client_ip()

        ok, _info = radius_check(user, pw)
        if ok:
            if not authorize(ip):
                print(f"[portal] NFT FAIL {user} from {ip}", flush=True)
                self._send(500, page(
                    "Ошибка портала",
                    "<p>RADIUS подтвердил вход, но не удалось добавить IP "
                    "в список разрешённых. Проверьте nftables на портале.</p>"))
                return
            target = take(ip) or DEFAULT_REDIRECT
            print(f"[portal] OK {user} from {ip} -> {target}", flush=True)
            # Именно редирект (а не страница «доступ разрешён»): браузер сам
            # открывает тот внешний сайт, который пользователь запрашивал.
            self._redirect(target)
        else:
            print(f"[portal] REJECT {user} from {ip}", flush=True)
            self._send(401, page(
                "Отказ в доступе",
                f"<p>RADIUS отклонил вход для <b>{html.escape(user)}</b>.</p>"
                + FORM))

    def log_message(self, *args):
        pass


def main():
    with http.server.ThreadingHTTPServer(("0.0.0.0", PORT), Handler) as srv:
        print(f"[portal] слушаю 0.0.0.0:{PORT}", flush=True)
        srv.serve_forever()


if __name__ == "__main__":
    main()