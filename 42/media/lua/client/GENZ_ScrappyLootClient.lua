-- Shows the owner which jewels Scrappy took off a corpse (card #246). The server sends the list;
-- in single player GENZ_ScrappyLootServer calls onLooted directly (no network there).
GENZ_ScrappyLootClient = GENZ_ScrappyLootClient or {}
local Client = GENZ_ScrappyLootClient

local NET = "GENZ_Scrappy"

function Client.onLooted(args)
    local player = getPlayer()
    if not player or not args or not args.items then return end
    local names = {}
    for i = 1, #args.items do
        names[#names + 1] = getItemNameFromFullType(args.items[i])
    end
    HaloTextHelper.addGoodText(player, getText("IGUI_Scrappy_Looted", table.concat(names, ", ")))
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= NET or command ~= "looted" then return end
    Client.onLooted(args)
end)
