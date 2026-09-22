// Copyright Armchair Developers. Licensed under GPLv3.
#pragma once

#include <cstdint>
#include <limits>
#include <map>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>

namespace Kyber::LocalizationCodec
{
using Bytes = std::vector<uint8_t>;
using Strings = std::map<uint32_t, std::u16string>;

struct Chunks
{
    Bytes binary;
    Bytes histogram;
};

inline uint32_t Read32(const Bytes& data, size_t offset)
{
    if (offset > data.size() || data.size() - offset < 4)
    {
        throw std::runtime_error("Truncated localization header");
    }
    return uint32_t(data[offset]) | (uint32_t(data[offset + 1]) << 8) |
        (uint32_t(data[offset + 2]) << 16) | (uint32_t(data[offset + 3]) << 24);
}

inline void Write32(Bytes& data, size_t offset, uint32_t value)
{
    for (size_t i = 0; i < 4; ++i)
    {
        data.at(offset + i) = static_cast<uint8_t>(value >> (8 * i));
    }
}

inline std::vector<uint16_t> ReadHistogram(const Bytes& data)
{
    const size_t size = Read32(data, 4);
    if (data.size() < 12 || size % 2 != 0 || size > data.size() - 12 || size < 512)
    {
        throw std::runtime_error("Invalid localization histogram size");
    }
    std::vector<uint16_t> values;
    values.reserve(size / 2);
    for (size_t i = 12; i < 12 + size; i += 2)
    {
        values.push_back(uint16_t(data[i]) | (uint16_t(data[i + 1]) << 8));
    }
    return values;
}

inline Strings Decode(const Bytes& binary, const Bytes& histogram)
{
    if (Read32(binary, 0) != 0x00039000)
    {
        throw std::runtime_error("Invalid localization binary magic");
    }
    const auto values = ReadHistogram(histogram);
    const size_t count = Read32(binary, 8);
    const uint64_t tableStart = uint64_t(Read32(binary, 12)) + 8;
    const uint64_t stringStart = uint64_t(Read32(binary, 16)) + 8;
    if (tableStart < 20 || tableStart > stringStart || stringStart > binary.size() ||
        count > (stringStart - tableStart) / 8)
    {
        throw std::runtime_error("Invalid localization string table");
    }
    Strings strings;
    for (size_t i = 0; i < count; ++i)
    {
        const uint32_t id = Read32(binary, static_cast<size_t>(tableStart) + i * 8);
        const uint64_t offset = stringStart + Read32(binary, static_cast<size_t>(tableStart) + i * 8 + 4);
        if (offset >= binary.size())
        {
            throw std::runtime_error("Invalid localization string offset");
        }
        size_t cursor = static_cast<size_t>(offset);
        std::u16string text;
        bool terminated = false;
        while (cursor < binary.size())
        {
            const uint8_t byte = binary[cursor++];
            if (byte == 0)
            {
                terminated = true;
                break;
            }
            uint16_t value = byte;
            if (byte >= 0x80)
            {
                value = values[byte];
                if (value < 0x80)
                {
                    if (cursor >= binary.size() || binary[cursor] < 0x80)
                    {
                        throw std::runtime_error("Invalid localization shift sequence");
                    }
                    const size_t index = (size_t(value) << 7) + binary[cursor++] - 0x80;
                    if (index >= values.size())
                    {
                        throw std::runtime_error("Localization histogram index out of bounds");
                    }
                    value = values[index];
                }
            }
            text.push_back(static_cast<char16_t>(value));
        }
        if (!terminated)
        {
            throw std::runtime_error("Unterminated localization string");
        }
        strings[id] = std::move(text);
    }
    return strings;
}

// Re-encode every string, not only replacements: existing text must use the same
// histogram as newly introduced Cyrillic/CJK/etc. The wire units are UTF-16,
// including surrogate pairs; neither UTF-8 bytes nor the system ANSI code page.
inline Chunks Merge(const Bytes& binary, const Bytes& histogram, const Strings& replacements)
{
    auto strings = Decode(binary, histogram);
    for (const auto& entry : replacements)
    {
        strings[entry.first] = entry.second;
    }
    std::set<uint16_t> alphabet;
    for (const auto& entry : strings)
    {
        for (char16_t ch : entry.second)
        {
            if (ch == 0)
            {
                throw std::runtime_error("Embedded NUL in localization text");
            }
            if (ch >= 0x80)
            {
                alphabet.insert(ch);
            }
        }
    }
    // A prefix stores a 7-bit page index. Pages 0 and 1 contain the prefix table.
    constexpr size_t kMaxCharacters = 126 * 128;
    if (alphabet.size() > kMaxCharacters)
    {
        throw std::runtime_error("Localization alphabet exceeds histogram capacity");
    }
    const size_t pages = (alphabet.size() + 127) / 128;
    std::vector<uint16_t> values(256 + pages * 128, 0);
    std::map<uint16_t, size_t> indices;
    size_t index = 0;
    for (uint16_t ch : alphabet)
    {
        values[256 + index] = ch;
        values[128 + index / 128] = static_cast<uint16_t>(2 + index / 128);
        indices[ch] = index++;
    }
    Chunks result;
    result.histogram.assign(histogram.begin(), histogram.begin() + 12);
    Write32(result.histogram, 4, static_cast<uint32_t>(values.size() * 2));
    for (uint16_t value : values)
    {
        result.histogram.push_back(static_cast<uint8_t>(value));
        result.histogram.push_back(static_cast<uint8_t>(value >> 8));
    }
    // Preserve any format-specific trailer following the declared table.
    const size_t oldEnd = 12 + Read32(histogram, 4);
    result.histogram.insert(result.histogram.end(), histogram.begin() + oldEnd, histogram.end());

    const size_t tableStart = size_t(Read32(binary, 12)) + 8;
    const size_t stringStart = tableStart + strings.size() * 8;
    result.binary.assign(binary.begin(), binary.begin() + tableStart);
    result.binary.resize(stringStart);
    Write32(result.binary, 8, static_cast<uint32_t>(strings.size()));
    Write32(result.binary, 16, static_cast<uint32_t>(stringStart - 8));
    index = 0;
    for (const auto& entry : strings)
    {
        Write32(result.binary, tableStart + index * 8, entry.first);
        Write32(result.binary, tableStart + index * 8 + 4, static_cast<uint32_t>(result.binary.size() - stringStart));
        for (char16_t ch : entry.second)
        {
            if (ch < 0x80)
            {
                result.binary.push_back(static_cast<uint8_t>(ch));
            }
            else
            {
                const size_t glyph = indices.at(ch);
                result.binary.push_back(static_cast<uint8_t>(0x80 + glyph / 128));
                result.binary.push_back(static_cast<uint8_t>(0x80 + glyph % 128));
            }
        }
        result.binary.push_back(0);
        ++index;
    }
    if (result.binary.size() - 8 > std::numeric_limits<uint32_t>::max())
    {
        throw std::runtime_error("Localization chunk exceeds 32-bit size");
    }
    Write32(result.binary, 4, static_cast<uint32_t>(result.binary.size() - 8));
    return result;
}
} // namespace Kyber::LocalizationCodec
