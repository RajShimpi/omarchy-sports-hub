"""Settings, paths, notifications and meeting detection shared by the
Sports Hub helpers (scripts/cricket and scripts/sports)."""
import copy, fcntl, json, os, re, subprocess

HOME = os.path.expanduser("~")
CONF = os.path.join(HOME, ".config/omarchy/sports-hub.json")
# Settings file of the plugin's first release, still read when the new one is missing.
LEGACY_CONF = os.path.join(HOME, ".config/omarchy/cricket.json")
CACHE_DIR = os.path.join(HOME, ".cache/omarchy/sports-hub")

TABS = ["live", "cricket", "football", "f1", "tennis", "basketball", "nfl", "hockey", "baseball", "golf", "mma"]

DEFAULTS = {
    "tabs": TABS,
    "follow": ["India"],
    "followTeams": [],
    "football": ["eng.1", "uefa.champions", "esp.1", "ind.1"],
    "leagues": {
        "basketball": ["nba"], "nfl": ["nfl"], "hockey": ["nhl"], "baseball": ["mlb"],
        "tennis": ["atp", "wta"], "golf": ["pga"], "mma": ["ufc"],
    },
    "f1": True,
    "notify": True,
    "ballAlerts": True,
    "quietWhenBusy": True,
    "companion": "",
}


def settings():
    s = copy.deepcopy(DEFAULTS)
    for path in (CONF, LEGACY_CONF):
        try:
            with open(path) as f:
                user = json.load(f)
        except (OSError, ValueError):
            continue
        if isinstance(user, dict):
            leagues = user.pop("leagues", None)
            s.update(user)
            if isinstance(leagues, dict):
                s["leagues"].update(leagues)
        break
    # "followClubs" is the old name of "followTeams".
    s["followTeams"] = list(s.get("followTeams") or []) + list(s.get("followClubs") or [])
    s.pop("followClubs", None)
    s["tabs"] = [t for t in s.get("tabs") or TABS if t in TABS]
    return s


def write_default_config():
    """Create the settings file (only when it doesn't exist yet), seeded with
    the current settings so an old cricket.json carries over."""
    if os.path.exists(CONF):
        return
    os.makedirs(os.path.dirname(CONF), exist_ok=True)
    with open(CONF, "w") as f:
        json.dump(settings(), f, indent=2)
        f.write("\n")


def locked(name):
    """An exclusive lock next to a cache file. Every bar (one per monitor)
    runs the helpers on its own timer; this makes them take turns."""
    os.makedirs(CACHE_DIR, exist_ok=True)
    lock = open(os.path.join(CACHE_DIR, name + ".lock"), "w")
    fcntl.flock(lock, fcntl.LOCK_EX)
    return lock


def load(name, default=None):
    try:
        with open(os.path.join(CACHE_DIR, name)) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {} if default is None else default


def save(name, data):
    path = os.path.join(CACHE_DIR, name)
    with open(path + ".tmp", "w") as f:
        json.dump(data, f)
    os.replace(path + ".tmp", path)


def busy():
    """In a meeting or sharing the screen, judged by window titles."""
    try:
        titles = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True, timeout=3).stdout
    except (OSError, subprocess.TimeoutExpired):
        return False
    return bool(re.search(r'"title":\s*"[^"]*(Meeting|Call with|Sharing|Huddle|Meet - )', titles, re.I))


def notify(title, body, glyph):
    subprocess.Popen(["omarchy-notification-send", "-g", glyph, title, body],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def companion(s, text, how="celebrate"):
    """Optionally pass the moment to another shell plugin over IPC, e.g. a
    desktop pet: `qs ipc call <companion> celebrate|sad "<text>"`."""
    target = s.get("companion") or ""
    if not re.fullmatch(r"[A-Za-z0-9._-]+", target):
        return
    shell = os.path.join(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy"), "shell")
    subprocess.Popen(["qs", "-p", shell, "ipc", "call", target, how, text],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
