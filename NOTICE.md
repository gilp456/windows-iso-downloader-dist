# Notices and attribution

Windows ISO Downloader

Copyright (C) 2026 gilp456

This runtime is licensed under the GNU General Public License, version 3 only (`GPL-3.0-only`). See [LICENSE](LICENSE).

## Massgrave catalog documentation

The runtime reads public installation-media catalog documentation maintained by Massgrave contributors at <https://github.com/massgravel/massgrave.dev>. That documentation is licensed under [Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/). The runtime parses the Markdown, normalizes headings and records, filters records using the user's selection, deduplicates provider links, and caches a structured snapshot. Those transformations are changes made by this project; Massgrave contributors do not endorse them.

The release package does not bundle the Microsoft Activation Scripts program and contains no activation functionality.

## Fido

For supported Microsoft consumer-media discovery, the runtime may download and execute an unmodified, SHA-256-pinned copy of `Fido.ps1` from commit [`266084e3765ab8bf96767bd55c51b0ee70934551`](https://github.com/pbatard/Fido/tree/266084e3765ab8bf96767bd55c51b0ee70934551). Fido is copyright © 2019–2026 Pete Batard and contributors and is licensed under GPL-3.0-or-later. Its [source](https://github.com/pbatard/Fido) and [license](https://github.com/pbatard/Fido/blob/master/LICENSE.txt) remain under their authors' terms. Fido and its license are fetched on demand into the user's tool cache and are not bundled in this release ZIP.

## Gravesoft MSDL

The runtime may read a SHA-256-pinned product catalog from Gravesoft's [MSDL project](https://github.com/gravesoft/msdl) at commit [`00433c88ab2ff1c7ae34a473d59735885de52846`](https://github.com/gravesoft/msdl/tree/00433c88ab2ff1c7ae34a473d59735885de52846) and query its public discovery API. The MSDL project is licensed under [AGPL-3.0](https://github.com/gravesoft/msdl/blob/main/LICENSE). MSDL code is not bundled in this release ZIP.

## TechLatest MSDL fallback

When the primary Microsoft-media discovery service is unavailable, the runtime may query `api.msdl.tech-latest.com`, operated from the [TechLatest Windows ISO Downloader project](https://github.com/starkSV/windows-iso-downloader). That project is copyright © 2026 TechLatest and licensed under the [MIT License](https://github.com/starkSV/windows-iso-downloader/blob/main/LICENSE). Its implementation code is not bundled in this release ZIP.

## Microsoft and provider material

The runtime may query Microsoft-operated services and independent providers solely to resolve or retrieve user-selected media. Microsoft installation media and other third-party payloads are not part of this licensed program and are not relicensed by this notice.

Microsoft, Windows, and Office are trademarks of the Microsoft group of companies. All other trademarks are the property of their respective owners.
