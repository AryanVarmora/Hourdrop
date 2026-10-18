# Sip: Mac water reminder + tracker

A real Mac app that lives in your menu bar, reminds you every 30 minutes (or the interval you choose), and lets you log water straight from the notification. No Xcode needed.

## Install (one time, about 2 minutes)
1. Unzip `Sip.zip` (e.g. into Downloads).
2. Open **Terminal** and run:
   ```
   cd ~/Downloads/Sip
   bash install.sh
   ```
3. First time only: if a popup asks to install **Command Line Tools**, click **Install**, wait for it to finish, then run `bash install.sh` again.
4. Sip opens. A drop and `0.0 L` appear in your menu bar.
5. Click **Allow** when macOS asks about notifications.

That's it. `Sip.app` is now in **/Applications** like any other app. You can open it from Launchpad or Spotlight (⌘Space → "Sip"), and delete the Downloads folder if you like.

## Set up (one time)
1. Click the drop → **Settings…**
   - Set your **bottle size** (type the exact ml; ounces show next to it) and **daily goal**
   - Pick how often reminders come: **every 30 minutes, 1 hour, 1½ hours or 2 hours**
   - Set your **wake hours** (reminders only fire inside them). They can run past midnight, e.g. From 10 AM Until 2 AM.
   - Turn on **Launch at login** so it starts every time your Mac boots
   - Click **Send a test reminder** to check it works
2. System Settings → **Notifications → Sip**:
   - Alert style: **Alerts** (they stay on screen until you tap a button; Banners vanish and you miss the log)
   - If macOS asks about Sip in **Login Items**, allow it

## Daily use
- Every 30 minutes a reminder appears. Have a drink, then hover it → **Options** → pick how much you drank: **¼ bottle, ½ bottle or Full bottle** (the ml amount is shown). Logged.
- Or click the drop in the menu bar and tap ¼ / ½ / Full.
- **Coffee, chai or a smoothie?** Click the drop, tap ☕️ Coffee, 🍵 Chai or 🥤 Smoothie, then pick a size: **10, 12, 16, 20, 24 or 30 oz**. For anything else, type it next to **Other** (e.g. 18) and click **Log**.
- From a reminder: **Options → ☕️ Coffee…** (or Chai… / Smoothie…), type the ounces (e.g. 30), then click **Log**. You can also type ml, like "355 ml".
- Every drink counts toward your daily goal. Under the total you'll see the split, e.g. 💧 1.3 L ☕️ 0.4 L.
- Tapped the wrong one? **Undo last** removes it.
- The menu bar always shows today's total. It resets at midnight.
- Your full history is saved in `~/Library/Application Support/Sip/water-log.json`.

## Updating
Change any file in `Sources/`, then run `bash install.sh` again. It rebuilds and replaces the installed app.

## Changing the icon
The icon is `Icon/AppIcon.icon`: a white drop with blue water, using macOS's glass style.
1. Double-click `Icon/AppIcon.icon` to open it in **Icon Composer** (comes with Xcode).
2. Change colours, glass or layers, then save.
3. Run `bash install.sh`. It rebuilds the icon and saves a ready-made copy in `Resources/`, so the install still works on Macs without Xcode.

If the old icon still shows in Finder or Launchpad, run `killall Dock` to refresh the icon cache.

## Uninstall
Quit Sip from its menu, delete `/Applications/Sip.app`, and optionally delete `~/Library/Application Support/Sip`.

## Troubleshooting
- **No notifications**: check Focus / Do Not Disturb is off, and System Settings → Notifications → Sip is allowed.
- **No permission prompt**: remove Sip from System Settings → Notifications, then reopen Sip.
- **"Apple could not verify Sip…" warning**: `install.sh` already removes the downloaded-file mark that causes it. If it still appears, open System Settings → Privacy & Security, scroll down and click **Open Anyway**. If you send `Sip.app` to someone else, they will see this warning. Only a paid Apple Developer account ($99/year) with notarization removes it on other Macs.
- **Build error**: copy the Terminal output and send it over.

## Files
| File | What it does |
|---|---|
| `install.sh` | Builds the app and icon, signs it locally, installs to /Applications, launches it |
| `Info.plist` | App identity and icon; `LSUIElement` makes it menu bar only (no Dock icon) |
| `Icon/AppIcon.icon` | The app icon source (open in Icon Composer) |
| `Resources/` | Built icon files (`AppIcon.icns`, `Assets.car`), made by `install.sh` |
| `Sources/SipApp.swift` | App entry, menu bar icon + live total |
| `Sources/WaterStore.swift` | Drink types and sizes; saves drinks, today's total, undo, midnight reset |
| `Sources/NotificationManager.swift` | Reminders (every 30 min by default) with ¼ / ½ / Full buttons that log water |
| `Sources/MenuBarView.swift` | Popover: progress, one-tap logging, today's log |
| `Sources/SettingsView.swift` | Bottle size, goal, reminder interval, wake hours, test reminder, launch at login |
