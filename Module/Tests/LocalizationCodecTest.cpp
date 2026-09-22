#include <ModLoader/LocalizationCodec.h>

#include <cassert>
#include <iostream>

using namespace Kyber::LocalizationCodec;

static Chunks Fixture()
{
    Chunks fixture;
    fixture.histogram.resize(12 + 512, 0);
    Write32(fixture.histogram, 0, 0x12345678);
    Write32(fixture.histogram, 4, 512);
    fixture.histogram[12 + 0x80 * 2] = 0xe9;
    fixture.binary.resize(0x94 + 16);
    Write32(fixture.binary, 0, 0x39000);
    Write32(fixture.binary, 8, 2);
    Write32(fixture.binary, 12, 0x8c);
    Write32(fixture.binary, 16, 0x8c + 16);
    fixture.binary[20] = 'e';
    fixture.binary[21] = 'n';
    Write32(fixture.binary, 0x94, 100);
    Write32(fixture.binary, 0x98, 0);
    Write32(fixture.binary, 0x9c, 200);
    Write32(fixture.binary, 0xa0, 4);
    fixture.binary.insert(fixture.binary.end(), {'O', 'l', 'd', 0, 'C', 'a', 'f', 0x80, 0});
    Write32(fixture.binary, 4, static_cast<uint32_t>(fixture.binary.size() - 8));
    return fixture;
}

template<typename F> static void MustReject(F action)
{
    bool rejected = false;
    try { action(); }
    catch (const std::runtime_error&) { rejected = true; }
    assert(rejected);
}

int main()
{
    const auto original = Fixture();
    const auto before = Decode(original.binary, original.histogram);
    assert(before.at(200) == u"Caf\u00e9");
    const Strings translations = {
        {100, u"\u041f\u0440\u0438\u0432\u0435\u0442, \u043c\u0438\u0440! \u0401\u0451"},
        {300, u"\u4e2d\u6587 \u65e5\u672c\u8a9e \u03a9 \U0001f680"},
        {400, u""},
    };
    const auto merged = Merge(original.binary, original.histogram, translations);
    const auto decoded = Decode(merged.binary, merged.histogram);
    for (const auto& entry : translations)
    {
        assert(decoded.at(entry.first) == entry.second);
    }
    assert(decoded.at(200) == before.at(200));
    assert(Read32(merged.histogram, 0) == Read32(original.histogram, 0));
    assert(merged.binary[20] == 'e' && merged.binary[21] == 'n');
    assert(Read32(merged.binary, 4) + 8 == merged.binary.size());
    const auto repeated = Merge(merged.binary, merged.histogram, {{100, u"Next"}});
    assert(Decode(repeated.binary, repeated.histogram).at(300) == translations.at(300));

    std::u16string many;
    for (uint16_t ch = 0x100; ch < 0x100 + 126 * 128; ++ch)
    {
        many.push_back(static_cast<char16_t>(ch));
    }
    auto full = Merge(original.binary, original.histogram, {{100, many}, {200, u"ASCII"}});
    assert(Decode(full.binary, full.histogram).at(100) == many);
    many.push_back(u'\uffff');
    MustReject([&] { Merge(original.binary, original.histogram, {{100, many}, {200, u"ASCII"}}); });
    auto malformed = original;
    Write32(malformed.histogram, 4, 0xfffffffe);
    MustReject([&] { Decode(malformed.binary, malformed.histogram); });
    malformed = original;
    Write32(malformed.binary, 0x98, 0xffffffff);
    MustReject([&] { Decode(malformed.binary, malformed.histogram); });
    malformed = original;
    Write32(malformed.binary, 8, 0xffffffff);
    MustReject([&] { Decode(malformed.binary, malformed.histogram); });
    malformed = original;
    malformed.binary.back() = 'x';
    MustReject([&] { Decode(malformed.binary, malformed.histogram); });
    assert(Decode(original.binary, original.histogram) == before);
    std::cout << "Localization codec: Unicode, preservation, paging, limits and malformed input passed\n";
}
