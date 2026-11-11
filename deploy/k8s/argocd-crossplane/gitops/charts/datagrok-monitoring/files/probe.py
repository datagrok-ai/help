#!/usr/bin/env python3
"""Datagrok instance probe (stdlib only).

/api/admin/health answers 200 while a dependency is down, so the probe reads the
body and reports each service; it also times the request, reads the certificate
and the signing key age, and signs in when it has an account for the instance.

The instances are probed in the background every PROBE_INTERVAL seconds and
/metrics serves the last result, so an instance that hangs never makes the scrape
time out and take the other instances' series with it.

Series, each labelled datagrok_instance, datagrok_url and, when set, tenant:
  datagrok_health_age_scrape_success    1 if /api/admin/health answered with a service list
  datagrok_health_duration_seconds      how long that took
  datagrok_health_age_seconds           age of the oldest service check
  datagrok_service_up{service}          1 = Running and enabled; a service that is switched
                                        off or not part of the deployment has no series
  datagrok_signing_key_age_seconds      age of the primary signing key (public JWKS)
  probe_ssl_earliest_cert_expiry        expiry of the certificate, Unix time
  datagrok_login_success                1 if the probe account signed in
  datagrok_login_duration_seconds
And one without labels:
  datagrok_probe_last_run_timestamp_seconds   when the last round finished
"""
import base64
import json
import os
import socket
import ssl
import threading
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LISTEN_PORT = int(os.environ.get("LISTEN_PORT", "9107"))
INTERVAL = float(os.environ.get("PROBE_INTERVAL", "30"))
LOGIN_INTERVAL = float(os.environ.get("LOGIN_INTERVAL", "300"))
TIMEOUT = float(os.environ.get("SCRAPE_TIMEOUT", "10"))
LOGIN_TIMEOUT = float(os.environ.get("LOGIN_TIMEOUT", "20"))
INSECURE = os.environ.get("INSECURE_SKIP_VERIFY", "") == "true"
AGENT = {"User-Agent": "datagrok-probe"}

VERIFIED = ssl.create_default_context()
CTX = ssl.create_default_context()
if INSECURE:
    CTX.check_hostname = False
    CTX.verify_mode = ssl.CERT_NONE


def _json_env(name, kind):
    raw = os.environ.get(name, "").strip()
    if not raw:
        return kind()
    try:
        parsed = json.loads(raw)
        return parsed if isinstance(parsed, kind) else kind()
    except ValueError:
        print("%s is not valid JSON - ignoring it" % name, flush=True)
        return kind()


INSTANCES = [i for i in _json_env("INSTANCES", list) if i.get("name") and i.get("url")]
CREDENTIALS = _json_env("LOGIN_CREDENTIALS", dict)

# Kept between rounds, per instance name.
_cert_expiry = {}   # the last expiry read: a certificate that has expired can no longer be read
_logins = {}        # (monotonic time, result): signing in every round would fill the audit log


def _parse_iso(t):
    return datetime.fromisoformat(t.replace("Z", "+00:00"))


def _get(url, timeout=TIMEOUT):
    req = urllib.request.Request(url, headers=AGENT)
    with urllib.request.urlopen(req, timeout=timeout, context=CTX) as r:
        return json.loads(r.read())


def health(root):
    """(ok, duration, oldest_age or None, {service: up})."""
    started = time.monotonic()
    try:
        data = _get(root + "/api/admin/health")
        if not isinstance(data, list) or not data:
            raise ValueError("not a service list")
    except Exception:
        return 0, time.monotonic() - started, None, {}
    duration = time.monotonic() - started
    now = datetime.now(timezone.utc)
    ages, services = [], {}
    for svc in data:
        if not isinstance(svc, dict):
            continue
        key = svc.get("key") or svc.get("name")
        status = svc.get("status")
        # Switched off in the settings, or not part of this deployment: a choice, not
        # an outage. Blocked: not checked because a service it depends on is down;
        # that one's series carries the outage.
        skipped = (status == "Stopped" and svc.get("description") == "Disabled") \
            or status in ("Not applicable", "Blocked")
        if key and not skipped:
            services[str(key)] = 1 if status == "Running" and svc.get("enabled", True) else 0
        # A Blocked check is not re-run; its old timestamp does not mean the checks stopped.
        t = None if status == "Blocked" else svc.get("time")
        if t:
            try:
                ages.append((now - _parse_iso(t)).total_seconds())
            except Exception:
                pass
    return 1, duration, (max(ages) if ages else None), services


def signing_key_age(root):
    try:
        keys = _get(root + "/api/.well-known/jwks.json").get("keys", [])
        stamps = [_parse_iso(k.get("rotated") or k.get("created")) for k in keys
                  if k.get("use") == "sig" and k.get("status") == "primary"
                  and (k.get("rotated") or k.get("created"))]
        if stamps:
            return (datetime.now(timezone.utc) - max(stamps)).total_seconds()
    except Exception:
        pass
    return None


def cert_expiry(name, root):
    url = urllib.parse.urlparse(root)
    if url.scheme != "https" or INSECURE:
        return None
    try:
        with socket.create_connection((url.hostname, url.port or 443), timeout=TIMEOUT) as s:
            with VERIFIED.wrap_socket(s, server_hostname=url.hostname) as t:
                not_after = (t.getpeercert() or {}).get("notAfter")
                if not_after:
                    _cert_expiry[name] = ssl.cert_time_to_seconds(not_after)
    except Exception:
        pass
    return _cert_expiry.get(name)


def login(name, root):
    """(success, duration), or None without an account for the instance."""
    entry = CREDENTIALS.get(name) or {}
    user, password = entry.get("user"), entry.get("password")
    if not user or not password:
        return None
    last = _logins.get(name)
    if last and time.monotonic() - last[0] < LOGIN_INTERVAL:
        return last[1]
    started = time.monotonic()
    try:
        # datlas base64-decodes the password field before comparing it.
        payload = json.dumps({
            "login": user,
            "password": base64.b64encode(password.encode()).decode(),
        }).encode()
        req = urllib.request.Request(
            root + "/api/users/login", data=payload, method="POST",
            headers=dict(AGENT, **{"Content-Type": "application/json"}))
        with urllib.request.urlopen(req, timeout=LOGIN_TIMEOUT, context=CTX) as r:
            body = json.loads(r.read() or b"{}")
        # A failed login still answers 200 with {"isSuccess": false}.
        result = (1 if body.get("isSuccess") else 0), time.monotonic() - started
    except Exception:
        result = 0, time.monotonic() - started
    _logins[name] = (time.monotonic(), result)
    return result


def _escape(value):
    return str(value).replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ")


def probe(instance):
    name, root = instance["name"], instance["url"].rstrip("/")
    labels = {"datagrok_instance": name, "datagrok_url": root}
    if instance.get("tenant"):
        labels["tenant"] = instance["tenant"]

    def line(metric, value, **extra):
        pairs = ",".join('%s="%s"' % (k, _escape(v)) for k, v in dict(labels, **extra).items())
        return "%s{%s} %s" % (metric, pairs, value)

    try:
        ok, duration, age, services = health(root)
    except Exception as x:  # one instance never takes the others down
        print("probe of %s failed: %r" % (name, x), flush=True)
        ok, duration, age, services = 0, 0.0, None, {}
    lines = [line("datagrok_health_age_scrape_success", ok),
             line("datagrok_health_duration_seconds", "%.3f" % duration)]
    if age is not None:
        lines.append(line("datagrok_health_age_seconds", "%.0f" % age))
    for service in sorted(services):
        lines.append(line("datagrok_service_up", services[service], service=service))
    key_age = signing_key_age(root) if ok else None
    if key_age is not None:
        lines.append(line("datagrok_signing_key_age_seconds", "%.0f" % key_age))
    expiry = cert_expiry(name, root)
    if expiry is not None:
        lines.append(line("probe_ssl_earliest_cert_expiry", "%.0f" % expiry))
    # An instance that does not answer is one outage, not a failed login as well.
    signed_in = login(name, root) if ok else None
    if signed_in is not None:
        lines.append(line("datagrok_login_success", signed_in[0]))
        lines.append(line("datagrok_login_duration_seconds", "%.3f" % signed_in[1]))
    return lines


HEADER = [
    "# TYPE datagrok_health_age_scrape_success gauge",
    "# TYPE datagrok_health_duration_seconds gauge",
    "# TYPE datagrok_health_age_seconds gauge",
    "# TYPE datagrok_service_up gauge",
    "# TYPE datagrok_signing_key_age_seconds gauge",
    "# TYPE probe_ssl_earliest_cert_expiry gauge",
    "# TYPE datagrok_login_success gauge",
    "# TYPE datagrok_login_duration_seconds gauge",
    "# TYPE datagrok_probe_last_run_timestamp_seconds gauge",
]

_result = None  # the exposition text of the last round


def collect():
    samples = []
    if INSTANCES:
        with ThreadPoolExecutor(max_workers=min(16, len(INSTANCES))) as pool:
            results = list(pool.map(probe, INSTANCES))
        # The exposition format wants the samples of one metric together.
        samples = sorted((l for lines in results for l in lines), key=lambda l: l.split("{", 1)[0])
    samples.append("datagrok_probe_last_run_timestamp_seconds %.0f" % time.time())
    return "\n".join(HEADER + samples) + "\n"


def run_forever():
    global _result
    while True:
        started = time.monotonic()
        try:
            _result = collect()
        except Exception as x:
            print("probe round failed: %r" % x, flush=True)
        time.sleep(max(1.0, INTERVAL - (time.monotonic() - started)))


class Handler(BaseHTTPRequestHandler):
    def _answer(self, code, body=b""):
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):  # noqa: N802
        if self.path == "/metrics":
            # Before the first round ends there is nothing to report.
            self._answer(200, _result.encode()) if _result else self._answer(503)
        elif self.path == "/healthz":
            self._answer(200, b"ok\n")
        else:
            self._answer(404)

    def log_message(self, *args):  # noqa: N802
        pass


if __name__ == "__main__":
    print("datagrok-probe on :%d for %s (login: %s)"
          % (LISTEN_PORT, [i["name"] for i in INSTANCES], sorted(CREDENTIALS)), flush=True)
    threading.Thread(target=run_forever, daemon=True).start()
    ThreadingHTTPServer(("0.0.0.0", LISTEN_PORT), Handler).serve_forever()
