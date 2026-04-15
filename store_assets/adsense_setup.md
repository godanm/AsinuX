# AdSense Setup — AsinuX Web

## Status
- [ ] AdSense account approved
- [ ] Domain kazhutha.app connected to Firebase
- [ ] Verification script added to index.html
- [ ] Ad units created
- [ ] Ad slots added to game

## Step 1 — After AdSense approval
Google will give you a verification script like:
```html
<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=ca-pub-XXXXXXXXXXXXXXXXX"
     crossorigin="anonymous"></script>
```
Paste this to Claude and it will inject it into `web/index.html` and redeploy.

## Step 2 — Create Ad Units in AdSense Console
Recommended units for AsinuX:
1. **Display ad** — for home screen / between games (responsive)
2. **In-article ad** — for results/stats screen

## Step 3 — Where to place ads in the app
- Home screen: banner below the PLAY NOW button
- Results screen: between round result and Next Round button
- Stats screen: bottom of page

## AdSense vs AdMob
| | AdSense | AdMob |
|---|---|---|
| Platform | Web only | Android / iOS |
| Approval | Site-level, 1–14 days | App-level, after Play Store publish |
| Status | Waiting for approval | Test IDs active, real IDs ready |

## Publisher ID
(fill in after approval)
`ca-pub-XXXXXXXXXXXXXXXXX`
