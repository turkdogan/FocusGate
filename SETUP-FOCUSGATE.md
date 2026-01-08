# FocusGate - Quick Setup Guide

You've created the empty FocusGate project. Let's add the source files!

## Current Structure

```
/Users/t/projects/FocusGate/
├── FocusGate.xcodeproj       ← Your empty project
├── FocusGate/                ← Xcode's default folder
│   ├── FocusGateApp.swift    ← Default (will replace)
│   └── ContentView.swift     ← Default (will delete)
├── FocusGate-Sources/        ← Our app code (ready to add)
├── FocusGateExtension-Sources/ ← Our extension code (ready to add)
├── Shared/                   ← Shared code (ready to add)
└── Resources/                ← Config files (ready to add)
```

## Step 1: Delete Xcode's Default Files (30 seconds)

In Xcode Project Navigator (left sidebar):

1. Find **ContentView.swift**
2. Right-click → Delete → Move to Trash

(Keep FocusGateApp.swift for now - we'll replace it)

## Step 2: Add Our App Files (1 minute)

1. **Right-click** the **FocusGate** folder (yellow folder in Xcode)
2. Choose **"Add Files to FocusGate..."**
3. Navigate to: `/Users/t/projects/FocusGate/FocusGate-Sources`
4. **Select ALL 5 files**:
   - FocusGateApp.swift
   - FilterManager.swift
   - BlockedSitesView.swift
   - RuleSetsView.swift
   - StatusView.swift
5. In options dialog:
   - ✅ **CHECK** "Copy items if needed"
   - ✅ **CHECK** "Create groups"
   - ✅ **CHECK** "FocusGate" target
6. Click **Add**

You'll now have TWO FocusGateApp.swift files (old and new).

## Step 3: Delete OLD FocusGateApp (10 seconds)

1. Find the OLD FocusGateApp.swift (the one that's ~10 lines, created by Xcode)
2. Right-click → Delete → Move to Trash

Now only our new one remains!

## Step 4: Add Shared Files (30 seconds)

1. **Right-click** the **FocusGate** folder again
2. Choose **"Add Files to FocusGate..."**
3. Navigate to: `/Users/t/projects/FocusGate/`
4. **Select the Shared FOLDER** (the whole folder)
5. In options:
   - ✅ **CHECK** "Copy items if needed"
   - ✅ **CHECK** "Create groups"
   - ✅ **CHECK** "FocusGate" target
6. Click **Add**

## Step 5: Build the App! (10 seconds)

Press **⌘B** (Product → Build)

**Expected**: Should build successfully! ✅

## Step 6: Create System Extension Target (1 minute)

1. **File → New → Target**
2. Select **macOS → System Extension**
3. Configure:
   - Product Name: **FocusGateExtension**
   - Bundle Identifier: **dev.turkdogan.FocusGate.Extension**
   - Starting Point: **Network Extension**
   - Provider Type: **Content Filter**
4. Click **Finish**
5. Click **"Activate"** when prompted

## Step 7: Add Extension Files (30 seconds)

1. Xcode created a **FocusGateExtension** folder - delete any files in it
2. **Right-click FocusGateExtension** folder
3. Choose **"Add Files to FocusGate..."**
4. Navigate to: `/Users/t/projects/FocusGate/FocusGateExtension-Sources`
5. **Select both files**:
   - FilterDataProvider.swift
   - main.swift
6. In options:
   - ✅ **CHECK** "Copy items if needed"
   - ✅ **CHECK** "Create groups"
   - ✅ **CHECK** "FocusGateExtension" target ONLY (not FocusGate!)
7. Click **Add**

## Step 8: Add Shared Files to Extension (30 seconds)

The Shared files need to be in BOTH targets!

1. In Project Navigator, find **Shared** folder
2. Click on **Models.swift**
3. In **File Inspector** (right sidebar):
   - Under "Target Membership"
   - ✅ **Check BOTH**: FocusGate AND FocusGateExtension
4. Repeat for:
   - DomainMatcher.swift
   - ConfigurationStore.swift
   - DecisionLogger.swift

## Step 9: Add Capabilities (1 minute)

### FocusGate target:
1. Select **FocusGate** target → **Signing & Capabilities**
2. Click **"+ Capability"** → **"App Groups"**
3. Click **"+"** button, enter: `group.dev.turkdogan.focusgate.shared`
4. ✅ Enable the checkbox

### FocusGateExtension target:
1. Select **FocusGateExtension** target → **Signing & Capabilities**
2. Click **"+ Capability"** → **"App Groups"**
3. Click **"+"** button, enter: `group.dev.turkdogan.focusgate.shared` (same!)
4. ✅ Enable the checkbox

## Step 10: Set Entitlements (1 minute)

1. **Right-click** project root → **"Add Files to FocusGate..."**
2. Navigate to: `/Users/t/projects/FocusGate/Resources`
3. Select all 3 files:
   - FocusGate.entitlements
   - FocusGateExtension.entitlements
   - FocusGateExtension-Info.plist
4. In options:
   - ✅ **CHECK** "Copy items if needed"
   - ✅ **CHECK** "Create groups"
   - ❌ **UNCHECK** all targets
5. Click **Add**

Now set them:
- **FocusGate target** → Build Settings → Search "entitlements"
  - Code Signing Entitlements: `Resources/FocusGate.entitlements`

- **FocusGateExtension target** → Build Settings → Search "entitlements"
  - Code Signing Entitlements: `Resources/FocusGateExtension.entitlements`

## Step 11: Build & Run! (10 seconds)

1. Select **"FocusGate"** scheme (top bar)
2. **Product → Build** (⌘B)
3. **Product → Run** (⌘R)

FocusGate should launch! 🎉

## Step 12: Enable the Filter (2 minutes)

1. In the app, go to **Blocked Sites** tab
2. Add a test site: `example.com`
3. Go to **Status** tab
4. Click **"Enable Filter"**
5. System will prompt → **Open System Settings**
6. Go to **Privacy & Security → Network Extensions**
7. **Approve FocusGate**
8. Done! Filter is active.

## Test It!

In Terminal:
```bash
curl -v http://example.com
# Should fail!
```

In Safari:
- Visit `example.com` → Should not load
- Check **Status** tab in app → See blocked entries

---

## Bundle Identifiers Reference

- **App**: `dev.turkdogan.FocusGate`
- **Extension**: `dev.turkdogan.FocusGate.Extension`
- **App Group**: `group.dev.turkdogan.focusgate.shared`

---

## Troubleshooting

**"main attribute cannot be used"**
- FocusGateApp.swift should be in FocusGate target ONLY
- main.swift should be in FocusGateExtension target ONLY

**"No such module"**
- Shared files must be in BOTH targets

**"App Group not available"**
- Both targets need App Groups capability
- Same identifier: `group.dev.turkdogan.focusgate.shared`

---

Total time: ~7 minutes to working app!
