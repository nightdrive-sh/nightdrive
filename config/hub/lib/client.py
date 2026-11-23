"""The Hub's requests (~/Projects/nightdrive-hub/docs/protocol.md), as a small client on the standard library.

One connection is kept for a whole sync (the Hub speaks HTTP/1.1): over Tailscale each new one is a TLS handshake.
A connection the Hub or a proxy closed meanwhile is opened again once. Errors come in three kinds the sync treats
differently:
- Offline: the Hub can't be reached (no network, the Hub machine asleep). Normal for a laptop: the changes wait.
- ServerChanged: another Hub answers at the URL than the one this computer joined (protocol.md › Info).
- HubError: the Hub answered with an error; `code` is the protocol's (`bad_name`, `path_clash`…).
"""
import http.client
import json
import ssl
from urllib.parse import quote, urlsplit

TIMEOUT = 30        # seconds: a file of 64 MiB over a slow link takes longer, but Tasks' are a few kB (Hub 7)
PROTOCOL = 1


class Offline(Exception):
    pass


class ServerChanged(Exception):
    pass


class HubError(Exception):
    def __init__(self, status, code, message):
        super().__init__("%s (%d %s)" % (message, status, code))
        self.status, self.code = status, code


class State:
    """A file's state on the Hub as a read or a 409 gives it: version 0 = no such file."""

    def __init__(self, version, hash_=None, deleted=False, body=b""):
        self.version, self.hash, self.deleted, self.body = version, hash_, deleted, body

    @classmethod
    def from_answer(cls, headers, body):
        return cls(int(headers.get("Hub-Version") or 0), headers.get("Hub-Hash"),
                   headers.get("Hub-Deleted") == "1", body)


class Conflict(Exception):
    """A 409: the write or deletion's base wasn't the Hub's version. `state` is the Hub's file now."""

    def __init__(self, state):
        super().__init__("conflict")
        self.state = state


def file_url(collection, path):
    # Segment by segment, as protocol.md › Requests says: a "/" in a name can't occur, every other character is
    # escaped, so "My note.md" and "#1.ics" reach the Hub as they are
    return "/v1/c/%s/files/%s" % (quote(collection, safe=""), "/".join(quote(s, safe="") for s in path.split("/")))


class Client:
    def __init__(self, url, server=None):
        u = urlsplit(url.rstrip("/"))
        if u.scheme not in ("http", "https") or not u.hostname:
            raise ValueError("A Hub's address is http(s)://HOST[:PORT], e.g. https://hub.tailnet.ts.net")
        self.scheme, self.host, self.port, self.prefix = u.scheme, u.hostname, u.port, u.path
        self.server = server        # the id every answer must carry; None until info() has told it
        self.conn = None

    def close(self):
        if self.conn:
            self.conn.close()
            self.conn = None

    def _connect(self):
        if self.scheme == "https":
            return http.client.HTTPSConnection(self.host, self.port, timeout=TIMEOUT,
                                               context=ssl.create_default_context())
        return http.client.HTTPConnection(self.host, self.port, timeout=TIMEOUT)

    def request(self, method, url, body=None, headers=None):
        """(status, headers, body). Opens the connection again once when a kept one has gone stale."""
        for attempt in (0, 1):
            if self.conn is None:
                self.conn = self._connect()
            try:
                self.conn.request(method, self.prefix + url, body=body, headers=headers or {})
                resp = self.conn.getresponse()
                data = resp.read()
                hdrs = {k.title(): v for k, v in resp.getheaders()}
                if hdrs.get("Connection", "").lower() == "close":
                    self.close()
                break
            except (http.client.RemoteDisconnected, BrokenPipeError, ConnectionResetError,
                    http.client.CannotSendRequest) as e:
                self.close()
                if attempt:
                    raise Offline("The Hub closed the connection: %s" % e)
            except (OSError, http.client.HTTPException) as e:
                # Refused, no route, a name that doesn't resolve, a timeout, a TLS failure: all "can't reach it now"
                self.close()
                raise Offline("Can't reach the Hub at %s: %s" % (self.host, e))
        server = hdrs.get("Hub-Server")
        if self.server and server and server != self.server:
            raise ServerChanged("Another Hub answers at this address (%s, not %s)" % (server, self.server))
        return resp.status, hdrs, data

    def _json(self, method, url, body=None, headers=None, ok=(200,)):
        status, hdrs, data = self.request(method, url, body, headers)
        if status in ok:
            return json.loads(data or b"{}")
        raise self._error(status, data)

    @staticmethod
    def _error(status, data):
        try:
            d = json.loads(data)
            return HubError(status, d.get("error", "?"), d.get("message", ""))
        except ValueError:
            return HubError(status, "?", "Not a Hub's answer")

    # The requests

    def info(self):
        d = self._json("GET", "/v1/info")
        if d.get("protocol") != PROTOCOL or not d.get("server"):
            raise HubError(200, "protocol", "Not a Nightdrive Hub of protocol %d" % PROTOCOL)
        return d

    def changes(self, collection, since):
        """Every change after `since`, page by page: yields (changes, cursor) per page."""
        while True:
            d = self._json("GET", "/v1/c/%s/changes?since=%d" % (quote(collection, safe=""), since))
            yield d["changes"], d["cursor"]
            since = d["cursor"]
            if not d.get("more"):
                return

    def get(self, collection, path):
        """State of a file with its content; version 0 when the Hub never had it."""
        status, hdrs, data = self.request("GET", file_url(collection, path))
        if status in (200, 410):
            return State.from_answer(hdrs, data)
        if status == 404:
            return State(0)
        raise self._error(status, data)

    def put(self, collection, path, body, base, hash_):
        """{"version", "hash", "changed"}; Conflict with the Hub's state on 409."""
        status, hdrs, data = self.request("PUT", "%s?base=%d" % (file_url(collection, path), base), body,
                                          {"Hub-Hash": hash_, "Content-Type": "application/octet-stream"})
        if status == 409:
            raise Conflict(State.from_answer(hdrs, data))
        if status != 200:
            raise self._error(status, data)
        return json.loads(data)

    def delete(self, collection, path, base):
        """{"version", "changed"}; Conflict on 409; None when the Hub has no such file (404)."""
        status, hdrs, data = self.request("DELETE", "%s?base=%d" % (file_url(collection, path), base))
        if status == 409:
            raise Conflict(State.from_answer(hdrs, data))
        if status == 404:
            return None
        if status != 200:
            raise self._error(status, data)
        return json.loads(data)
