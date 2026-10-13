"""Builds index.json from cars/*/meta.json and checks every car folder. Exit code 1 on a problem."""
import hashlib, json, os, re, sys, zipfile

ALLOWED = {"CC0-1.0", "CC-BY-4.0", "CC-BY-SA-4.0", "CC-BY-NC-4.0", "CC-BY-NC-SA-4.0"}
MAX = 50 * 1024 * 1024
problems, cars = [], []
for cid in sorted(os.listdir("cars")):
    d = os.path.join("cars", cid)
    if not os.path.isdir(d):
        continue
    if not re.fullmatch(r"[a-z0-9_]{1,64}", cid):
        problems.append(f"{cid}: folder name must be a-z 0-9 _")
        continue
    try:
        meta = json.load(open(os.path.join(d, "meta.json"), encoding="utf-8"))
    except Exception as e:
        problems.append(f"{cid}: meta.json unreadable ({e})")
        continue
    pkg = os.path.join(d, "car.bmwcar")
    if not os.path.isfile(pkg) or not os.path.isfile(os.path.join(d, "thumbnail.png")):
        problems.append(f"{cid}: needs car.bmwcar and thumbnail.png")
        continue
    data = open(pkg, "rb").read()
    if len(data) > MAX:
        problems.append(f"{cid}: car.bmwcar is over 50 MB")
    sha = hashlib.sha256(data).hexdigest()
    if meta.get("sha256", "").lower() != sha:
        problems.append(f"{cid}: sha256 in meta.json does not match car.bmwcar")
    if meta.get("license") not in ALLOWED:
        problems.append(f"{cid}: license must be one of {sorted(ALLOWED)}")
    if meta.get("id") != cid:
        problems.append(f"{cid}: meta.json id must equal the folder name")
    try:
        with zipfile.ZipFile(pkg) as z:
            names = z.namelist()
            if "car.json" not in names:
                problems.append(f"{cid}: car.bmwcar has no car.json")
            for n in names:
                if n.startswith("/") or ".." in n.split("/"):
                    problems.append(f"{cid}: bad path in package: {n}")
            if sum(i.file_size for i in z.infolist()) > 200 * 1024 * 1024:
                problems.append(f"{cid}: package unpacks to over 200 MB")
    except zipfile.BadZipFile:
        problems.append(f"{cid}: car.bmwcar is not a zip")
    entry = {k: meta.get(k) for k in ("id", "name", "author", "license", "description", "version", "size", "sha256", "triangles", "updated", "publisher")}
    entry["size"] = len(data)
    entry["sha256"] = sha
    cars.append(entry)

for p in problems:
    print("PROBLEM:", p)
if "--write" in sys.argv and not problems:
    json.dump({"format": 1, "cars": cars}, open("index.json", "w", encoding="utf-8"), indent=2, ensure_ascii=False)
    print(f"index.json: {len(cars)} car(s)")
sys.exit(1 if problems else 0)
