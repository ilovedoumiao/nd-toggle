<img src="nd-toggle/Assets.xcassets/AppIcon.appiconset/ND Toggle-macOS-Dark-256x256@2x.png" alt="ND Toggle icon" width="128px" style="vertical-align: middle; margin-right: 8px;" />

# ND Toggle

ND Toggle is a tiny unofficial menubar utility to conveniently start or stop your `nextdns-cli` daemon.
If you're like me—prefers the cli version, yet lazy to manually stop or start your NextDNS service through Terminal, this is for you.

## Disclaimer + TOS

Use this at your own risk. It works for me, but I can’t guarantee it will work as expected on your setup. By using ND Toggle, I assume no responsibility if it messes up your system.

## Getting Started

### Download the release

1. Download [ND-Toggle.app.zip here](https://github.com/ilovedoumiao/nd-toggle/releases)
2. Unzip file and move the app to your Applications folder
3. Open ND Toggle and find it on your menu bar with the shield icon.

#### Notes

You'd need to already have `nextdns-cli` installed. [See instructions here](https://github.com/nextdns/nextdns/wiki).

Release is not notarized so you may need to right click and choose Open from the context menu once.

or

### Build from source

```bash
git clone https://github.com/ilovedoumiao/nd-toggle.git
```

#### Notes

I've set the project to build for only `arm64` so change accordingly if you need a Universal build.
