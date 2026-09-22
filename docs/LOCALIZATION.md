# Unicode localization mods

The previous localization handler discarded every replacement character absent
from the base language's histogram. It also searched for two-byte prefixes using
an unchecked negative offset and truncated candidate prefix indices to one byte.
A translation using Cyrillic characters missing from an English histogram could
therefore become empty or corrupt even though the mod contained UTF-16 text.

The new codec decodes the original database, merges replacements, and rebuilds
both the byte string table and its UTF-16 histogram. Original strings and the
database header/tag are preserved. Each modified database gets its own chunk IDs
so a shared original histogram is not changed under another database. Invalid
input or an alphabet exceeding the format's capacity leaves the original chunks
intact and produces an error in the module log instead of publishing empty text.

The codec handles Cyrillic (including Ё/ё), other scripts and UTF-16 surrogate
pairs. This fixes text encoding, not missing glyphs in a custom font. It does not
guarantee that a particular localization mod supplies compatible font resources.

Run `tools\run-localization-tests.cmd` from Windows with Visual C++ Build Tools
2022 installed, or from a Visual Studio developer command prompt. The standalone
test covers Cyrillic, CJK, Greek, surrogate pairs, original text preservation,
repeated merges, all supported prefix pages, capacity and malformed input.

The exact user-reported Russian mod has not been supplied or tested in-game.
