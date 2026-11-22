-- Butchering parts for Scrappy. Without an AnimalPartsDefinitions entry the vanilla butchering
-- crashes on a nil def.feather. Prototype uses the base default (dog meat); a mechanical dog
-- should drop scrap instead, which needs a new item and is left for later.
if CompanionDogs and CompanionDogs.defineDogParts then
    CompanionDogs.defineDogParts("scrappy", "scrappy")
end
