// Copyright Armchair Developers. Licensed under GPLv3.

#include <Entity/Overrides/LocalizedStringIdPickerEntity.h>

#include <Entity/KyberSettings.h>
#include <Core/Program.h>

namespace Kyber
{
KB_IMPLEMENT_ENTITY_OVERRIDE(LocalizedStringIdPickerEntity, LocalizedStringIdPickerEntityData);

LocalizedStringIdPickerEntity::LocalizedStringIdPickerEntity(EntityManager* entityManager, NativeEntity* entity, LocalizedStringIdPickerEntityData* data)
    : KyberEntity(entity, data)
{
    m_localizedStringId = CreateFieldOverride<LocalizedStringId>("StringId", g_program->m_entityManager->GetNativeType("LocalizedStringId"));
    GetLocalized();
}

void LocalizedStringIdPickerEntity::PropertyChanged(PropertyModification* modification)
{
    GetLocalized();
}

// Gets the Sid input to the entity either from a connection or the entity data and creates a LocalizedStringId instance to output to StringId
void LocalizedStringIdPickerEntity::GetLocalized()
{
    // Entities can be created without a consumer for StringId. Frostbite's
    // property setter requires a bound output cache; do not call it otherwise.
    if (!m_localizedStringId.HasConnection())
    {
        return;
    }

    auto sidField = GetFieldReader<char*>("Sid");
    const char* sid = GetData()->Sid;
    if (sidField.HasConnectionValue())
    {
        const void* value = sidField.PropertyReaderBase::Get();
        if (value != nullptr)
        {
            sid = *static_cast<char* const*>(value);
        }
    }
    std::string id = sid != nullptr ? sid : "";
    int32_t stringHash = CalcStringHash(id);

    LocalizedStringId* container = g_program->m_entityManager->CreateContainer<LocalizedStringId>("LocalizedStringId");
    if (container == nullptr)
    {
        return;
    }
    container->StringHash = stringHash;

    m_localizedStringId = container;
}

// Strings in Frostbite are referenced by a hash of a unique ID for each string, This calculates that hash for a given ID and returns it
int32_t LocalizedStringIdPickerEntity::CalcStringHash(const std::string& string)
{
    int32_t result = 0xFFFFFFFF;
    for (int i = 0; i < string.length(); i++)
    {
        result = string[i] + 33 * result;
    }
    return result;
}
} // namespace Kyber
