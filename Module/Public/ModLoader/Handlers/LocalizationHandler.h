#pragma once

#include <ModLoader/CustomAssetHandler.h>

#include <map>

namespace Kyber
{
struct LocalizationMergeData : public CustomAssetHandlerData
{
    std::map<uint32_t, std::wstring> strings;
};

class LocalizationHandler : public GenericCustomAssetHandler<LocalizationMergeData>
{
public:
    LocalizationHandler();

    void Load(const eastl::string& modName, bb::ByteBuffer& buf, LocalizationMergeData* data) override;
    bool Modify(CustomAssetHandlerContext& ctx, DataContainer* container, LocalizationMergeData* data) override;

};
} // namespace Kyber
