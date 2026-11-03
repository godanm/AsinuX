# AdSense review for Tricksy web

## Site and verification

The public pages use `https://www.tricksy.app/` in their canonical tags, sitemap and robots file. Firebase Hosting may also serve the app on other connected domains. Check the preferred host and any domain redirects in the Firebase console before requesting review.

In AdSense, open the site entry and follow the verification instructions shown there. This repository already publishes `donkey_master/web/ads.txt` and loads the AdSense script on editorial pages. Check that the live `/ads.txt` returns HTTP 200 and that its publisher ID matches the AdSense account. Search Console verification is separate from AdSense verification.

## Preview before publishing

Run `flutter build web --release --pwa-strategy=none` in `donkey_master`, then run `firebase emulators:start --only hosting --project demo-tricksy` to preview locally. Check the app root, game links, guide redirects, privacy and terms pages, and an unknown URL. Unknown URLs should return HTTP 404. The eight playable game links should still open the app and send `X-Robots-Tag: noindex`.

After an approved Hosting release, verify the same routes on the public domain, submit `/sitemap.xml` in Search Console and inspect representative guide URLs. Review the site status, verification and privacy messaging in the AdSense account, including any consent requirements for the regions served. Keep ads away from navigation and game controls.

[AdSense site readiness](https://support.google.com/adsense/answer/7299563) · [Ads.txt setup](https://support.google.com/adsense/answer/12171612) · [Google consent requirements](https://support.google.com/adsense/answer/13554116)
