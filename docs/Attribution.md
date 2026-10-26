# Design and text sources

The user supplied `jaali-sample-standalone.html` as a design reference. Auralis adapts its palette, ground/tile/raised distinction, lattice idea and easing rhythm into original SwiftUI/AppKit views. The user's requested heavier typography is implemented with the native system font. No embedded Jaali font, HTML page or JavaScript library is redistributed.

Artwork, metadata, queue entries and optional lyrics come from the user's first-party YouTube Music session. All playback and entitlement checks remain with that website. Lyrics are read only from its rendered Lyrics tab, kept in memory and labeled as unsynchronized; no independent lyrics database or timing service is used.

Optional artist-story excerpts are obtained from English Wikipedia through its documented [MediaWiki Query API](https://www.mediawiki.org/wiki/API:Query) and [TextExtracts module](https://www.mediawiki.org/wiki/Extension:TextExtracts#API). The app links the matching article and labels the excerpt as Wikipedia / CC BY-SA. Text remains subject to the article's attribution and [Creative Commons Attribution-ShareAlike license](https://creativecommons.org/licenses/by-sa/4.0/). No Wikipedia images are fetched for this feature. The live service check resolved [Low Roar](https://en.wikipedia.org/wiki/Low_Roar); article prose is not embedded in this source distribution.
