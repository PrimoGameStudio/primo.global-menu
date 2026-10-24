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
| `desktop-fallback` | `.desktop` actions + window operations        |

`desktop-fallback` is the generic App/File/Edit/View/Window/Help menu. Seeing
it for an app that *does* have a menu bar means the extraction failed.

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
