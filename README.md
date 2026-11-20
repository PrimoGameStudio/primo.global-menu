# primo.global-menu

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/A3D729DKXZ)

A macOS-style application menu bar for Omarchy. The bar shows the focused
window's own menu (File / Edit / View / …) and lets you trigger its items
with the mouse.

## Layout

```
BarWidget.qml        bar slot: renders the menu strip, owns the open popup
MenuList.qml         one vertical menu; self-nesting for submenus
GlobalMenuData.qml   watches the bridge snapshot (active.json)
bin/omarchy-global-menu-bridge
                     the daemon: extracts the focused app's menu and
                     publishes it as JSON
systemd/omarchy-global-menu.service
                     user unit that runs the daemon
```

The daemon writes `~/.local/state/omarchy/global-menu/active.json`; the bar
widget `FileView`-watches that file and renders whatever it contains.

## Installation

The daemon has to run for the widget to show anything:

```bash
ln -sfn ~/.config/omarchy/plugins/primo.global-menu/systemd/omarchy-global-menu.service \
        ~/.config/systemd/user/omarchy-global-menu.service
ln -sfn ~/.config/omarchy/plugins/primo.global-menu/bin/omarchy-global-menu-bridge \
        ~/.local/bin/omarchy-global-menu-bridge
systemctl --user daemon-reload
systemctl --user enable --now omarchy-global-menu.service
```

The `~/.local/bin` symlink is only for calling the CLI by hand; the widget
resolves the bridge relative to the plugin directory.

## Where menus come from

The daemon walks a cascade for the focused window and uses the first hit:

| source          | mechanism                                        |
| --------------- | ------------------------------------------------ |
| `org.gtk.Menus` | GTK3's exported menubar model                    |
| `dbusmenu`      | `com.canonical.dbusmenu` (KDE/Electron apps)     |
| `at-spi`        | the accessibility tree (Qt, GTK4, Electron)      |
| `harvest`       | title-bar popovers, opened to be read (opt-in)   |
| `desktop-fallback` | `.desktop` actions + window operations        |

`desktop-fallback` is the generic App/File/Edit/View/Window/Help menu. Seeing
it for an app that *does* have a menu bar means the extraction failed.

A `dbusmenu` root is only accepted as a menubar when most of its entries are
submenus. Some apps export a flat menu at `/MenuBar` — OBS publishes its tray
menu there — and rendering that as a menubar would show `Hide`, `Start
Streaming` and `Exit` as if they were File and Edit.

## The AppMenu.Registrar

The daemon serves `com.canonical.AppMenu.Registrar` for the whole session.
Two app classes only export a menu when something is listening for one:

- **Qt6/KDE** registers its window menu with a registrar, or with Plasma's
  `kded` appmenu module, and exports nothing when neither is present.
- **LibreOffice** (GTK3 VCL) is a registrar client, and only hides its own
  menubar once the registrar answers. Without one the app draws its menus and
  the bar draws them again.

On a Plasma session the registrar is Plasma's. Elsewhere nobody owns the name,
which is why these apps showed the fallback. If another registrar already owns
it, the daemon logs that and carries on unchanged: it never displaces one.

Because LibreOffice hides its own menubar through GTK rather than the
registrar, the setting that actually removes the duplicate is:

```ini
# ~/.config/gtk-3.0/settings.ini
[Settings]
gtk-shell-shows-menubar=1
```

## Harvesting title-bar menus

Some apps never expose a `MENU_BAR` accessible. Their menubar is a row of
title-bar buttons, and a dropdown exists only while its button is open: the
accessibility tree has nothing to read at rest. Zed is one of these.

Set `harvestMenus` to have the daemon open each title-bar entry, read the
popup, close it again, and publish what it found:

```json
// ~/.config/omarchy/global-menu.json
{ "harvestMenus": true }
```

It is off by default because those popups flash on screen while the snapshot
is built. Results are memoised per window title, so a focus change does not
re-flash them.

The strip is found by shape, not by app: a container whose accessible name
says "title" (never one saying "status", which holds toggle buttons), with at
least three sibling buttons. The first entry is treated as the application
menu, and the menubar ends at the first button that opens nothing.

Apps that need it also need accessibility switched on inside the app itself.
Zed only builds an accessible tree when the experimental adapter is enabled:

```bash
ZED_EXPERIMENTAL_A11Y=1 zeditor
```

## Live menu updates

Every snapshot is normalized to put a `|` top-level item between the app menu
and the rest of the strip (`App Name | File Edit …`). Apps that already ship a
native `|` item (Devpad) are left as-is; for everyone else the bridge inserts
one, so the bar looks consistent regardless of the extraction source.

The bridge refreshes the focused app's menu when that menu changes, not just
on focus changes:

- GTK3 (`org.gtk.Menus`) and dbusmenu apps emit D-Bus change signals, which the
  daemon subscribes to directly.
- Apps that expose their menus only through AT-SPI — Qt Quick apps such as
  Devpad, GTK4 and Electron — are watched through AT-SPI `children-changed`,
  name and state events. Events are filtered to the focused window's process
  and debounced. A rebuild is published only when the menu content really
  changed, so a checkmark toggle or a growing "Recent Files" submenu updates
  the bar immediately without rewriting the snapshot for unrelated a11y
  traffic.

For apps that emit no usable change signal at all, periodic re-extraction can
be enabled with:

```json
// ~/.config/omarchy/global-menu.json
{ "pollIntervalSec": 5 }
```

`0` (the default) leaves refresh purely event-driven.

## Icon tinting

Monochrome icons can be recolored with the active Omarchy theme accent. It is
off by default; enable it in the widget's `shell.json` entry:

```json
// ~/.config/omarchy/shell.json — under bar.layout.<section>
{ "id": "primo.global-menu", "tintMonochromeIcons": true }
```

The bar's app icon is tinted per pixel: desaturated (white/grey) parts follow
the accent, while colored parts keep their own palette. This works for any
source — a themed name, an absolute path to a single-color SVG, or a PNG — with
no reliance on the icon's name. Menu item icons still use the freedesktop
`-symbolic` convention, and the Nerd Font glyph fallback is tinted directly.

The accent follows theme changes live, so tinted icons restyle without a shell
restart.

## Redundant separators

Toolkits collapse redundant separators when they lay out a native menu: a
separator that directly follows another one gets no geometry, so the app
shows a single line. The accessibility tree still lists both actions, and
the bar draws one row per action — which would show a double gap the app
itself never renders.

The bridge therefore drops any separator that directly follows another one
(`normalize_menus()`), applied to every extraction path. Two things produce
them: an app that adds a separator twice, and an app that hides an action
that sat between two separators (Qt drops hidden actions from the tree but
keeps the separators).

## Accessibility is required

at-spi2-core 2.62 (shipped with the October 2026 update) removed
`org.a11y.Status.ScreenReaderEnabled` and re-purposed `IsEnabled` to mean
"some client registered for AT-SPI events". Qt reads that flag to decide
whether to activate its AT-SPI bridge:

```cpp
enabled = QT_LINUX_ACCESSIBILITY_ALWAYS_ON
          || status.ScreenReaderEnabled || status.IsEnabled
```

With no registered listener, Qt apps export an empty accessible tree, so the
daemon finds no menubar and falls back to `desktop-fallback`.

The daemon therefore registers itself as an AT-SPI event listener on the
accessibility bus at startup (and re-registers every few seconds, and after an
a11y bus restart). That keeps `IsEnabled` true for the whole session, which
turns the AT-SPI bridge on in every app.

`~/.config/environment.d/99-a11y-always-on.conf` sets
`QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1` as a second line of defence: it forces
the bridge on even while the daemon is not running.

## Manual use

```bash
omarchy-global-menu-bridge --once      # write one snapshot and exit
omarchy-global-menu-bridge --debug     # verbose logging
omarchy-global-menu-bridge activate --action-json '{"kind":"exec","command":"true"}'
```

## Known limitations

- Apps that were already running when accessibility was enabled keep an empty
  accessible tree until they are restarted.
- Applications without a menu bar of their own (terminals, browsers) always
  show the `desktop-fallback` menu.
- GTK4/libadwaita apps (Nautilus, Papers, Pinta) have no menubar at all, only
  a hamburger popover. They show `desktop-fallback`; harvesting the popover
  would present an application menu as if it were File/Edit/View.
- Electron apps that hide their menu in the frame (GitHub Desktop, Obsidian,
  LocalSend) export nothing over any of these protocols.
- Harvesting needs the app's own accessible tree to be switched on, and on a
  freshly opened window some menubar entries open no popup at all — Zed's
  `Run`, `Window` and `Help` behave that way until the window has a project
  open. The harvest ends the menubar at that point rather than inventing
  entries.
- While the daemon serves the registrar, apps that registered with it keep a
  menu only as long as it runs. It restarts on failure, and it never takes the
  name from a registrar that already owns it.
