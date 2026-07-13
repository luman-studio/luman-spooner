-- ============================================================================
-- spooner :: client/data_loader.lua
-- Loads the correct per-game data tables (Peds, Animations, Vehicles, ...) at
-- runtime.
--
-- Why not in fxmanifest: the manifest is parsed before any game context exists,
-- so it cannot tell FiveM from RedM. Both games' data files define the SAME
-- globals (Peds, Animations, ...), so they collide if both sets load — exactly
-- one set must be chosen, and the manifest has no reliable signal to choose with.
-- Config.isRDR (set in config.lua via GetGameName) IS reliable at runtime, so we
-- pick the set here and execute the files in this shared Lua state, defining the
-- same globals the manifest used to. This runs before every other client module
-- so the data is ready for them.
--
-- The load list lives once, in fxmanifest's `spooner_data` metadata key. We read
-- it back here (GetResourceMetadata is a shared native, fine on the client — this
-- is exactly how ox_lib enumerates its own modules) and execute only the entries
-- for the running game. Add a data file to `spooner_data` and it's picked up here
-- automatically; nothing to change in this file.
-- ============================================================================

local resource = GetCurrentResourceName()
local prefix = ('data/%s/'):format(Config.isRDR and 'rdr3' or 'gta5')

for i = 0, GetNumResourceMetadata(resource, 'spooner_data') - 1 do
	local path = GetResourceMetadata(resource, 'spooner_data', i)

	if path and path:sub(1, #prefix) == prefix then
		local source = LoadResourceFile(resource, path)

		if not source then
			print(('[spooner] data file unreadable (is it in fxmanifest files{}?): %s'):format(path))
		else
			-- Bind _ENV = _G explicitly so the tables the file defines (Peds, ...)
			-- land in the shared global table the other client modules read from.
			local chunk, err = load(source, ('@%s/%s'):format(resource, path), 't', _G)

			if chunk then
				chunk()
			else
				print(('[spooner] failed to load %s: %s'):format(path, err))
			end
		end
	end
end
