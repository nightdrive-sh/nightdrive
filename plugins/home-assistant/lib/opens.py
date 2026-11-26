"""What running a scene, a script or an automation would open or unlock, which Access's unlock choice covers as it
covers a lock or a cover set directly (#1880, #1923). bin/home-assistant asks it for Claude's `set … run`.

A scene sets the entities it lists, and its states aren't in what Home Assistant tells: one that lists a lock or a cover
(or a group of one) counts, whether it locks or unlocks. A script or an automation is read from Home Assistant's config
(its sequence, its actions), with what those start in turn: a scene, a script, another automation. One whose config
can't be read (made in YAML outside the UI's files, or a token whose user isn't an admin) counts as one that opens, as
a group that can't be read does: Claude's call is refused rather than run on a guess.
"""
import re
import urllib.parse

ENTITY = re.compile(r"[a-z_]+\.[a-z0-9_]+")
# What opens or unlocks: the domains the unlock choice covers. A group of them counts as they do
OPENS = ("lock", "cover")
# What a script or automation may tell a lock or a cover without the unlock choice: as much as Claude's own set may
SAFE = {"lock.lock", "cover.close_cover", "cover.close_cover_tilt", "cover.stop_cover", "cover.stop_cover_tilt"}
SAFE_DEVICE = {"lock", "close", "close_tilt", "stop", "stop_tilt"}   # a device action's type
# Keys that hold conditions or triggers, not actions: a lock's state in an "if" opens nothing
NOT_ACTIONS = {"if", "conditions", "condition", "while", "until", "wait_for_trigger", "wait_template", "triggers",
               "trigger"}
# Targets a call can name besides entity ids: one of them may be a door's
OTHER_TARGETS = {"area_id", "device_id", "floor_id", "label_id"}
# How many scenes, scripts and automations one run is followed through; past it, what's left counts as opening
MAX_FOLLOW = 25
UNREAD = " (can't be read)"


def opens_in(c, now, nested=False):
    """The locks and covers a scene (or a group in it, one level down) sets, by id: running it does what they do"""
    members = now.get("attributes", {}).get("entity_id")
    members = [m for m in members if isinstance(m, str)] if isinstance(members, list) else []
    out = [m for m in members if m.split(".", 1)[0] in OPENS]
    for m in members:
        if m.split(".", 1)[0] == "group" and not nested:
            try:
                group = c.call("GET", "/api/states/" + m) if ENTITY.fullmatch(m) else None
                out += opens_in(c, group if isinstance(group, dict) else {}, nested=True)
            except Exception:
                out.append(m)   # a group that can't be read may hold one: counted, so it's refused rather than run
    return out


def templated(v):
    return isinstance(v, str) and ("{{" in v or "{%" in v)


def calls_in(node, out):
    """The service calls, scene shorthands and device actions in a sequence of actions, however deep (choose, if,
    parallel, repeat, sequence), into out"""
    if isinstance(node, list):
        for n in node:
            calls_in(n, out)
        return
    if not isinstance(node, dict):
        return
    service = node.get("action", node.get("service", node.get("service_template")))
    if isinstance(service, str) or isinstance(node.get("scene"), str) \
            or ("device_id" in node and "domain" in node and "condition" not in node):
        out.append(node)
        return
    if "condition" in node:   # a condition among the actions: it only decides whether the rest run
        return
    for k, v in node.items():
        if k not in NOT_ACTIONS:
            calls_in(v, out)


def named(call):
    """The entity ids a call names anywhere in it (its target, entity_id, scene.apply's entities), and whether it also
    names something another way: an area, a device, a floor, a label, a template"""
    ids, other = [], False

    def look(v, key=""):
        nonlocal other
        if key in OTHER_TARGETS and v:
            other = True
        if isinstance(v, str):
            other = other or templated(v)
            ids.extend(i for i in re.split(r"[\s,]+", v) if ENTITY.fullmatch(i))
        elif isinstance(v, list):
            for x in v:
                look(x, key)
        elif isinstance(v, dict):
            for k, x in v.items():
                if isinstance(k, str) and ENTITY.fullmatch(k):
                    ids.append(k)
                look(x, k)

    look({k: v for k, v in call.items() if k not in ("action", "service", "service_template")})
    return ids, other


def what(c, call):
    """What one call opens, and the scenes, scripts and automations it starts (followed by the caller)"""
    if isinstance(call.get("scene"), str) and not isinstance(call.get("action", call.get("service")), str):
        return [], [call["scene"]]
    if "device_id" in call and not isinstance(call.get("action", call.get("service")), str):
        domain = call.get("domain")
        if domain in OPENS and call.get("type") not in SAFE_DEVICE:
            return [call.get("entity_id") if isinstance(call.get("entity_id"), str) else f"a {domain} device"], []
        return [], []
    service = call.get("action", call.get("service", call.get("service_template")))
    if templated(service) or "." not in service:
        return [f"{service!r}{UNREAD}"], []
    domain, name = service.split(".", 1)
    if service in SAFE:
        return [], []
    ids, other = named(call)
    hits = opens_in(c, {"attributes": {"entity_id": ids}})   # locks and covers, and groups one level down
    if domain in OPENS and not hits:
        hits = [service]   # an area's, a device's or a template's: which ones isn't known
    elif domain == "homeassistant" and other:
        hits.append(f"{service} by area, device or template{UNREAD}")
    starts = domain in ("scene", "script", "homeassistant") and name not in ("turn_off", "reload")
    follow = [i for i in ids if i.split(".", 1)[0] in ("scene", "script")] if starts else []
    if domain == "script" and name not in ("turn_on", "toggle", "turn_off", "reload"):
        follow.append(service)   # script.goodnight called as a service of its own
    if service == "automation.trigger":
        follow += [i for i in ids if i.startswith("automation.")]
    if starts and other or service == "automation.trigger" and other:
        hits.append(f"{service} by area, device or template{UNREAD}")
    return hits, follow


def config(c, eid, now):
    """A script's or an automation's config from Home Assistant, None when it can't be read"""
    kind, _, key = eid.partition(".")
    try:
        if kind == "automation":   # the config's id isn't the entity's: Home Assistant gives it as an attribute
            now = now if isinstance(now, dict) else c.call("GET", "/api/states/" + eid)
            key = now.get("attributes", {}).get("id")
        if not isinstance(key, str) or not key:
            return None
        got = c.call("GET", f"/api/config/{kind}/config/{urllib.parse.quote(key, safe='')}")
    except Exception:
        return None
    return got if isinstance(got, dict) else None


def opens(c, eid, now=None, seen=None):
    """What running eid (a scene, a script, an automation) would open or unlock: lock and cover ids, a service, or
    what can't be read, marked UNREAD. Empty when nothing."""
    seen = set() if seen is None else seen
    if eid in seen:
        return []
    seen.add(eid)
    if len(seen) > MAX_FOLLOW or not ENTITY.fullmatch(eid):
        return [eid + UNREAD]
    kind = eid.split(".", 1)[0]
    if kind == "scene":
        try:
            now = now if isinstance(now, dict) else c.call("GET", "/api/states/" + eid)
        except Exception as e:
            # A scene Home Assistant doesn't have (one deleted that an automation still names) sets nothing
            return [] if getattr(e, "code", None) == 404 else [eid + UNREAD]
        return opens_in(c, now if isinstance(now, dict) else {})
    if kind not in ("script", "automation"):
        return []
    cfg = config(c, eid, now)
    if cfg is None:
        return [eid + UNREAD]
    calls = []
    calls_in(cfg.get("sequence") if kind == "script" else cfg.get("actions", cfg.get("action")), calls)
    hits = []
    for call in calls:
        h, follow = what(c, call)
        hits += h
        for f in follow:
            hits += opens(c, f, seen=seen)
    return hits


def refusal(c, eid, now):
    """Why Claude may not run this scene, script or automation without the unlock choice: what it would open or unlock,
    or that it can't be told. None when it opens nothing."""
    hit = set(opens(c, eid, now))
    if not hit:
        return None
    known = sorted(h for h in hit if not h.endswith(UNREAD))
    unread = sorted(h[:-len(UNREAD)] for h in hit if h.endswith(UNREAD))
    why = []
    if known:
        why.append(("it sets " if eid.startswith("scene.") else "it may open or unlock ") + ", ".join(known))
    if unread:
        why.append(f"what {', '.join(unread)} does can't be read from Home Assistant (a script's or an "
                   "automation's config needs an admin's token, and one in YAML outside the UI's files has none), so "
                   "it may open or unlock")
    return (f"{eid} wasn't run: {'; '.join(why)}, and the user's Access (Settings › Claude › Access › Home Assistant) "
            "lets Claude only lock locks and close covers. That is theirs to do; don't try it another way.")


def card_line(c, eid, now):
    """The card's Sets row for a scene, script or automation that would open or unlock (with the unlock choice on);
    "" when it opens nothing"""
    return ", ".join(sorted(set(opens(c, eid, now))))
