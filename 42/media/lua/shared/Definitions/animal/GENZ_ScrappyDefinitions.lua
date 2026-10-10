-- Scrappy animal types. Same skeleton, animset and dog behaviour as the base mod; prototype body is
-- the German Shepherd mesh (GermanShepherd_Body, shipped by Companion Dogs) with a Scrappy texture.
-- Separate "scrappy*" types because the engine binds a mesh/texture per type, not per breed.
-- Size tier is the German Shepherd's, same as the Doberman add-on uses.
-- Gate: without the base mod (0.6.3+) the add-on stays inert.
if not (CompanionDogs and CompanionDogs.applyDogModel and CompanionDogs.DOG_SOUNDS) then return end
local CD = CompanionDogs

local BODY_MODEL = "GermanShepherd_Body"   -- replace with "Scrappy_Body" when our own mesh exists

AnimalDefinitions = AnimalDefinitions or {}
AnimalDefinitions.stages = AnimalDefinitions.stages or {}
AnimalDefinitions.breeds = AnimalDefinitions.breeds or {}
AnimalDefinitions.animals = AnimalDefinitions.animals or {}

AnimalDefinitions.stages["scrappy"] = {}
AnimalDefinitions.stages["scrappy"].stages = {}
AnimalDefinitions.stages["scrappy"].stages["scrappypup"] = {}
AnimalDefinitions.stages["scrappy"].stages["scrappypup"].ageToGrow = 3 * 30
AnimalDefinitions.stages["scrappy"].stages["scrappypup"].nextStage = "scrappyfemale"
AnimalDefinitions.stages["scrappy"].stages["scrappypup"].nextStageMale = "scrappymale"
AnimalDefinitions.stages["scrappy"].stages["scrappymale"] = {}
AnimalDefinitions.stages["scrappy"].stages["scrappymale"].ageToGrow = 3 * 30
AnimalDefinitions.stages["scrappy"].stages["scrappyfemale"] = {}
AnimalDefinitions.stages["scrappy"].stages["scrappyfemale"].ageToGrow = 3 * 30

local breed = {}
breed.name = "scrappy"
breed.texture = "Scrappy"
breed.textureMale = "Scrappy"
breed.rottenTexture = "Raccoon_Rotting"
breed.invIconMale = "CDDogPaw_64"
breed.invIconFemale = "CDDogPaw_64"
breed.invIconBaby = "CDDogPaw_64"
breed.invIconMaleDead = "CDDogPawDead_64"
breed.invIconFemaleDead = "CDDogPawDead_64"
breed.invIconBabyDead = "CDDogPawDead_64"
breed.invIconMaleSkel = "Item_Skeleton_Raccoon"
breed.invIconFemaleSkel = "Item_Skeleton_Raccoon"
breed.invIconBabySkel = "Item_Skeleton_Raccoon"
breed.sounds = CD.DOG_SOUNDS

AnimalDefinitions.breeds["scrappy"] = {}
AnimalDefinitions.breeds["scrappy"].breeds = {}
AnimalDefinitions.breeds["scrappy"].breeds["scrappy"] = breed

local scrappypup = {}
CD.applyDogModel(scrappypup, BODY_MODEL)
CD.applyDogBehaviour(scrappypup)
scrappypup.shadoww = 0.2
scrappypup.shadowfm = 0.2
scrappypup.shadowbm = 0.2
scrappypup.minSize = 1.12
scrappypup.maxSize = 1.68
scrappypup.wanderMul = 500
scrappypup.hungerMultiplier = 0.001
scrappypup.thirstMultiplier = 0.002
scrappypup.hungerBoost = 25
scrappypup.thirstBoost = 30
scrappypup.baseEncumbrance = 10
scrappypup.trailerBaseSize = 30
scrappypup.minEnclosureSize = 40
scrappypup.needMom = false
scrappypup.eatFromMother = true
scrappypup.litterEatTogether = true
scrappypup.minWeight = 1
scrappypup.maxWeight = 8
scrappypup.wildFleeTimeUntilDeadTimer = CD.STRAY_NO_BLEEDOUT
scrappypup.breeds = AnimalDefinitions.breeds["scrappy"].breeds
scrappypup.stages = AnimalDefinitions.stages["scrappy"].stages
scrappypup.genes = AnimalDefinitions.genome["dog"].genes
AnimalDefinitions.animals["scrappypup"] = scrappypup

local scrappyfemale = {}
CD.applyDogModel(scrappyfemale, BODY_MODEL)
CD.applyDogBehaviour(scrappyfemale)
scrappyfemale.female = true
-- No `mate` on purpose: with it the engine runs its NATIVE mating, which ignores the base mod's
-- breeding toggle (see the base DogDefinitions.lua). Scrappy cannot breed anyway (canBreed=false).
scrappyfemale.babyType = "scrappypup"
scrappyfemale.shadoww = 0.3
scrappyfemale.shadowfm = 0.5
scrappyfemale.shadowbm = 0.5
scrappyfemale.minSize = 1.68
scrappyfemale.maxSize = 2.24
scrappyfemale.wanderMul = 600
scrappyfemale.hungerMultiplier = 0.008
scrappyfemale.thirstMultiplier = 0.016
scrappyfemale.hungerBoost = 20
scrappyfemale.thirstBoost = 25
scrappyfemale.baseEncumbrance = 20
scrappyfemale.trailerBaseSize = 50
scrappyfemale.minEnclosureSize = 40
scrappyfemale.minAge = 3 * 30
scrappyfemale.maxAgeGeriatric = 19 * 30
scrappyfemale.minAgeForBaby = 3 * 30
scrappyfemale.timeBeforeNextPregnancy = 7
scrappyfemale.pregnantPeriod = 35
scrappyfemale.minWeight = 9
scrappyfemale.maxWeight = 16
scrappyfemale.wildFleeTimeUntilDeadTimer = CD.STRAY_NO_BLEEDOUT
scrappyfemale.breeds = AnimalDefinitions.breeds["scrappy"].breeds
scrappyfemale.stages = AnimalDefinitions.stages["scrappy"].stages
scrappyfemale.genes = AnimalDefinitions.genome["dog"].genes
AnimalDefinitions.animals["scrappyfemale"] = scrappyfemale

local scrappymale = {}
CD.applyDogModel(scrappymale, BODY_MODEL)
CD.applyDogBehaviour(scrappymale)
scrappymale.male = true
scrappymale.babyType = "scrappypup"
scrappymale.dontAttackOtherMale = true
scrappymale.shadoww = 0.3
scrappymale.shadowfm = 0.5
scrappymale.shadowbm = 0.5
scrappymale.minSize = 1.68
scrappymale.maxSize = 2.43
scrappymale.wanderMul = 600
scrappymale.hungerMultiplier = 0.008
scrappymale.thirstMultiplier = 0.016
scrappymale.hungerBoost = 20
scrappymale.thirstBoost = 25
scrappymale.baseEncumbrance = 20
scrappymale.trailerBaseSize = 50
scrappymale.minEnclosureSize = 40
scrappymale.minAge = 3 * 30
scrappymale.maxAgeGeriatric = 19 * 30
scrappymale.minAgeForBaby = 3 * 30
scrappymale.minWeight = 10
scrappymale.maxWeight = 18
scrappymale.wildFleeTimeUntilDeadTimer = CD.STRAY_NO_BLEEDOUT
scrappymale.breeds = AnimalDefinitions.breeds["scrappy"].breeds
scrappymale.stages = AnimalDefinitions.stages["scrappy"].stages
scrappymale.genes = AnimalDefinitions.genome["dog"].genes
AnimalDefinitions.animals["scrappymale"] = scrappymale

AnimalAvatarDefinition = AnimalAvatarDefinition or {}
AnimalAvatarDefinition["scrappypup"] = {}
AnimalAvatarDefinition["scrappyfemale"] = {}
AnimalAvatarDefinition["scrappymale"] = {}
CD.applyDogAvatar(AnimalAvatarDefinition["scrappypup"])
CD.applyDogAvatar(AnimalAvatarDefinition["scrappyfemale"])
CD.applyDogAvatar(AnimalAvatarDefinition["scrappymale"])
