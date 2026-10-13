# Car marketplace

Cars for the **BMW M4 / custom cars** Minecraft mod (Fabric 1.21.11). Browse and install them in game:
press **U**, then **Marketplace**.

## Publishing
In game: **U > My cars > Publish**. The mod logs in to GitHub with a device code, forks this repository,
uploads the car and opens a pull request. When the pull request is merged, the car shows up for everyone.

Every car is a folder `cars/<id>/` with:

| File | What |
|---|---|
| `car.bmwcar` | the car: a zip with `car.json`, the glTF model and its textures |
| `thumbnail.png` | 256x144 preview |
| `meta.json` | name, author, license, size, sha256 (the mod writes it) |

`index.json` is rebuilt by a GitHub Action from every `meta.json` on each push to `main`. Don't edit it by hand.

## Rules
- Only publish models you made yourself or whose license allows sharing (CC0, CC BY, CC BY-SA, CC BY-NC, CC BY-NC-SA).
  Credit the original author in the car's author/description. "All rights reserved" models are rejected.
- No models ripped from games.
- 50 MB per car at most.
- Pull requests are checked automatically (files, size, checksum, license) and then reviewed by hand.
