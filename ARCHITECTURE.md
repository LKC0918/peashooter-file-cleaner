# Architecture

This is the public source edition. Runtime artwork, audio and app icons are
not included. Supply original or licensed local assets according to
`Resources/ASSET_SOURCES.md` before a full build or visual verification.

## Targets

### Peashooter File Cleaner

The menu-bar host application owns all visible UI, animation and file operations.

- `AppDelegate` starts an accessory app with a status item and receives both the custom URL scheme and Finder file-open compatibility requests. Every Finder entry hides the control panel before starting an experience.
- `AppCoordinator` validates every request again, then resolves the Finder visual target asynchronously before creating an experience.
- `AnimationWindowController` owns a non-interactive transparent overlay plus a separate interactive confirmation panel.
- `PeashooterScene` renders compact SpriteKit movement, shots, overlays, dynamic icon fragments and the stretcher exit.
- `TrashService` exposes only `FileManager.trashItem`; no permanent-delete API exists in the production target.

### PeashooterFinderExtension

The Finder Sync extension monitors Desktop, Documents and Downloads and contributes one contextual command for a single selected file. The host validates the file type and safety policy.

When Finder asks for the contextual menu, the extension captures `NSEvent.mouseLocation`. Capturing the point at menu creation is more accurate than waiting until the pointer has moved onto the menu command. When the command is selected, the extension obtains `selectedItemURLs()`, revalidates the single file, and opens:

```text
peashooter-cleaner://summon?file=<encoded-file-url>&x=<screen-x>&y=<screen-y>
```

Opening the URL starts the host app when necessary. The host parses and validates the request independently. File paths are not written to the application log.

### Finder Quick Action compatibility entry

On macOS versions where Finder starts a Finder Sync extension but does not call `menu(for:)`, the installed Finder-scoped Quick Action contributes the same top-level **召唤豌豆射手** command. It accepts exactly one Finder file and asks Launch Services to open that file with the installed `~/Applications/Peashooter File Cleaner.app`. Using the installed path prevents Xcode debug copies with the same bundle identifier from receiving the request. While the host is waiting in the background, it records the most recent global right-click point so the Quick Action does not mistake the later menu-item click for the Finder icon. Launch Services starts the app when needed; `AppDelegate` recognizes the incoming `file://` URL and passes it to the same `AppCoordinator` validation path. The Quick Action never moves, deletes or reads the file itself.

Finder Sync remains the primary implementation on systems where its menu callback is available. Both entries converge before file validation and the two confirmation steps. A global right-click is retained only when Finder was the frontmost application; unrelated clicks in other apps are ignored.

This local prototype keeps the host app unsandboxed so it can move the confirmed user file to Trash after receiving the selected path. The extension remains sandboxed. A distributable/App Store build should replace the path handoff with an App Group plus a security-scoped bookmark and enable the host app sandbox.

## State machine

```text
hidden
  → summoned
  → approaching
  → firstConfirmation
  → finalConfirmation
  → charging
  → shooting
  → trashing
  → shattering
  → success
  → zombieExit
  → hidden
```

Cancellation returns from either confirmation state to `hidden`. Runtime failures transition to `failure`, display an error without hiding the real icon, then return to `hidden`. Every state transition is checked before its animation or file side effect starts. The final-confirm button is deliberately unarmed for 500 ms after the first panel switches, preventing a double-click or repeated Return key from satisfying both safety boundaries.

The fifth pea launches while the state is still `shooting`. Only when it visibly reaches the target does the controller enter `trashing` and call `TrashService`. The impact is held pending until success, then impact and shatter start immediately; failure removes the pending pea without a final impact. Demo mode follows the same animation states but bypasses the service and never has a real file URL.

## Window model

- The full-screen `AnimationOverlayPanel` ignores all mouse events, never becomes key and uses the status-bar window level so its sprites stay above Finder without covering system-security surfaces.
- `ConfirmationPanelController` owns a small, separately positioned key panel. Only this panel can receive clicks.
- For a real file, the host first identifies the selected Finder item on a dedicated background queue with element-count and time limits. An exact AX URL match is accepted; a selected filename-only match is accepted only inside Finder's focused window. The matched filename/cell is then resolved to the nearest `AXImage` in its own container, and the projectile targets that image frame's geometric center instead of the filename or full row. It never requests the permission automatically.
- If Accessibility is unavailable and the exact requested file is directly on the Desktop, the host asks Finder for its one selected item's `desktop position` through an Apple Event. The returned path must exactly match the validated request and the converted point must lie on a connected screen. This makes a cold Quick Action launch work without confusing the later menu click with the icon. Other trusted fallbacks remain the original Finder Sync context point or a recent right-click recorded while Finder was frontmost; a menu-command click is always rejected.
- Global Finder coordinates are converted into the chosen `NSScreen`'s local coordinates by subtracting the screen frame origin, which also supports displays with negative origins.
- The captured file texture remains hidden during summon, both real-file confirmation panels and the first four hits. High-contrast double-stroked cracks, impact splats, shock rings and particles are drawn over Finder's real icon. Only demo mode displays a virtual file icon and caption.
- When the fifth pea reaches the icon, `trashItem` runs. On success, the hidden texture is divided immediately into 16 longer-lived fragments at the icon's last position, on the same visual beat that Finder removes the real item. The full duplicate icon is never revealed and there is no post-Trash polling delay.
- Character geometry is centralized in `ExperienceLayout`: the peashooter is 68×68 points, zombies are 63×96 points and the stretcher is 190×45 points. Muzzle, projectile, impact and attack distance derive from the same layout values.

## Stretcher exit

`PeashooterScene` builds a visible SpriteKit stretcher from two shaded wooden poles, a green canvas bed, straps and end grips. Two walk-animation characters and the stretcher enter inside one `zombieCarryGroup`. At pickup, the peashooter is reparented into that group and plays a struggle animation. The single group moves until its complete bounds are beyond the right edge, preventing character drift. Supply permitted local textures for the characters.

## Safety boundary

`FileSafetyPolicy` requires all of the following:

- the item exists;
- it is strictly inside the current user's home directory;
- it is a single regular file;
- it is neither a symbolic link nor an application bundle;
- it is not in a protected system root.

The Finder extension validates selection cardinality; the host performs the authoritative safety validation when it receives the request. That validation records the regular file's device and inode from `lstat`. After both confirmations and after the fifth pea reaches the target, `TrashService` enters an `NSFileCoordinator` moving operation, re-runs the complete policy inside that coordinated block, compares the stable identity, and only then calls `FileManager.trashItem`. Replacing the path while the dialogue is open therefore stops the attack instead of trashing the replacement. No final impact or shatter is allowed on failure.
