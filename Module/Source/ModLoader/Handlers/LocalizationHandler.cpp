// Copyright Armchair Developers / Sean Kahler. Licensed under GPLv3.

#include <ModLoader/Handlers/LocalizationHandler.h>
#include <ModLoader/LocalizationCodec.h>
#include <ModLoader/ModLoader.h>
#include <Core/Program.h>

#include <cstring>
#include <memory>

namespace Kyber
{
LocalizationHandler::LocalizationHandler()
    : GenericCustomAssetHandler(CustomAssetHandlerLoadStage_PostLoad)
{}

void LocalizationHandler::Load(const eastl::string& modName, bb::ByteBuffer& buf, LocalizationMergeData* data)
{
    uint32_t magic = buf.getInt();
    int32_t count = magic == 0xABCD0001 ? buf.getInt() : static_cast<int32_t>(magic);
    for (int32_t i = 0; i < count; ++i)
    {
        uint32_t hash = buf.getInt();
        data->strings[hash] = buf.getNullTerminatedWideString();
    }
}

bool LocalizationHandler::Modify(CustomAssetHandlerContext& ctx, DataContainer* container, LocalizationMergeData* data)
{
    UITextDatabase* db = static_cast<UITextDatabase*>(container);
    try
    {
        LocalizationCodec::Bytes histogram(db->HistogramChunkSize);
        LocalizationCodec::Bytes binary(db->BinaryChunkSize);
        ModLoader::ReadChunkSync(db->HistogramChunk, histogram.data(), db->HistogramChunkSize);
        ModLoader::ReadChunkSync(db->BinaryChunk, binary.data(), db->BinaryChunkSize);

        LocalizationCodec::Strings replacements;
        for (const auto& entry : data->strings)
        {
            replacements[entry.first] = std::u16string(entry.second.begin(), entry.second.end());
        }
        const auto merged = LocalizationCodec::Merge(binary, histogram, replacements);
        const Guid binaryId = Guid::Generate();
        const Guid histogramId = Guid::Generate();
        if (binaryId.IsZero() || histogramId.IsZero())
        {
            throw std::runtime_error("Failed to allocate localization chunk IDs");
        }

        // Validate and allocate both chunks before publishing either one. Invalid
        // input must leave the original database intact, never an empty chunk.
        auto newBinary = std::make_unique<uint8_t[]>(merged.binary.size());
        auto newHistogram = std::make_unique<uint8_t[]>(merged.histogram.size());
        std::memcpy(newBinary.get(), merged.binary.data(), merged.binary.size());
        std::memcpy(newHistogram.get(), merged.histogram.data(), merged.histogram.size());
        // Other databases may share the original histogram. Give this database
        // its own pair of chunks, served by the mod loader's GUID override map.
        ModLoader::ModifyChunk(histogramId, newHistogram.release(), static_cast<uint32_t>(merged.histogram.size()));
        ModLoader::ModifyChunk(binaryId, newBinary.release(), static_cast<uint32_t>(merged.binary.size()));
        db->HistogramChunk = histogramId;
        db->BinaryChunk = binaryId;
        db->HistogramChunkSize = static_cast<uint32_t>(merged.histogram.size());
        db->BinaryChunkSize = static_cast<uint32_t>(merged.binary.size());
        KYBER_LOG(Info, "[ModLoader] Merged Unicode localization (" << replacements.size() << " replacements)");
        return true;
    }
    catch (const std::exception& error)
    {
        KYBER_LOG(Error, "[ModLoader] Localization merge failed; preserving original text: " << error.what());
        return false;
    }
}
} // namespace Kyber
