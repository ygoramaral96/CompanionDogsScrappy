-- Shows the owner which jewels Scrappy took off a corpse. The server sends the list through
-- CompanionDogsScrappy.toOwner (network in MP, a direct call in single player).
require "CompanionDogsScrappyShared"
local S = CompanionDogsScrappy

S.clientHandlers.looted = function(args)
    local player = getPlayer()
    if not player or not args or not args.items then return end
    local names = {}
    for i = 1, #args.items do
        names[#names + 1] = getItemNameFromFullType(args.items[i])
    end
    HaloTextHelper.addGoodText(player, getText("IGUI_Scrappy_Looted", table.concat(names, ", ")))
end
