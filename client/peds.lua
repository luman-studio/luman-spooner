-- ============================================================================
-- spooner :: client/peds.lua
-- Saved Peds, MP Peds (session clones), and saved Animation+Prop presets
--
-- Part of the split client.lua. All spooner client modules share one Lua state
-- and _G, so globals defined in any module are visible to the others.
-- ============================================================================

-- Saved Peds: persist a single ped (model + animation/scenario + extras) so it
-- can be re-spawned later from the "Saved Peds" category in the spawn menu.

local SAVED_PED_PREFIX = 'SAVEDPED_'

function BuildSavedPedProps(handle, savedName)
	if not DoesEntityExist(handle) then
		return nil
	end

	local db = Database[handle] or {}
	local model = db.model or GetEntityModel(handle)

	-- Capture any props attached to the ped so they can be re-spawned and
	-- re-attached when the saved ped is loaded.
	local attachments = {}
	for _, child in ipairs(GetAttachedChildren(handle)) do
		local cdb = Database[child]
		if cdb and cdb.attachment then
			local a = cdb.attachment
			table.insert(attachments, {
				name = cdb.name,
				model = cdb.model,
				type = cdb.type,
				attachment = {
					bone = a.bone,
					x = a.x, y = a.y, z = a.z,
					pitch = a.pitch, roll = a.roll, yaw = a.yaw,
					useSoftPinning = a.useSoftPinning,
					collision = a.collision,
					vertex = a.vertex,
					fixedRot = a.fixedRot
				}
			})
		end
	end

	return {
		savedName = savedName,
		name = db.name or GetModelName(model),
		model = model,
		outfit = db.outfit or -1,
		animation = db.animation,
		scenario = db.scenario,
		weapons = db.weapons or {},
		walkStyle = db.walkStyle,
		scale = db.scale,
		pedConfigFlags = db.pedConfigFlags or (GetEntityType(handle) == 1 and GetPedConfigFlags(handle) or nil),
		blockNonTemporaryEvents = db.blockNonTemporaryEvents or false,
		attachments = attachments,
		behavior = db.behavior
	}
end

function SaveSavedPed(props)
	SetResourceKvp(SAVED_PED_PREFIX .. props.savedName, json.encode(props))
end

function LoadSavedPed(name)
	local content = GetResourceKvpString(SAVED_PED_PREFIX .. name)
	return content and json.decode(content)
end

function GetSavedPeds()
	local peds = {}

	local handle = StartFindKvp(SAVED_PED_PREFIX)

	while true do
		local kvp = FindKvp(handle)

		if kvp then
			table.insert(peds, string.sub(kvp, #SAVED_PED_PREFIX + 1))
		else
			break
		end
	end

	EndFindKvp(handle)

	table.sort(peds)

	return peds
end

function DeleteSavedPed(name)
	DeleteResourceKvp(SAVED_PED_PREFIX .. name)
end

RegisterNUICallback('saveCurrentPed', function(data, cb)
	if data.name and data.name ~= '' and DoesEntityExist(data.handle) then
		local props = BuildSavedPedProps(data.handle, data.name)

		if props then
			SaveSavedPed(props)
		end
	end

	cb(json.encode(GetSavedPeds()))
end)

RegisterNUICallback('getSavedPeds', function(data, cb)
	cb(json.encode(GetSavedPeds()))
end)

RegisterNUICallback('deleteSavedPed', function(data, cb)
	DeleteSavedPed(data.name)
	cb({})
end)

RegisterNUICallback('renameSavedPed', function(data, cb)
	if data.oldName and data.newName and data.newName ~= '' and data.newName ~= data.oldName then
		local saved = LoadSavedPed(data.oldName)

		if saved then
			saved.savedName = data.newName
			SaveSavedPed(saved)
			DeleteSavedPed(data.oldName)
		end
	end

	cb(json.encode(GetSavedPeds()))
end)

-- ===================== MP Peds =====================
-- MP (freemode) ped appearance is captured two ways:
--  - A hidden ClonePed "template" for the CURRENT session — exact, zero-effort,
--    used whenever it's still alive (fast path, perfect fidelity).
--  - A component-variation snapshot (drawable/texture/palette per slot), which is
--    what actually gets written to disk (KVP) and survives a resource/server
--    restart. It won't capture things a plain component copy can't (e.g. custom
--    face sliders), but it reproduces clothing/hair/etc. closely for most looks.

SavedMpPeds = SavedMpPeds or {}

local MP_PED_PREFIX = 'MPPED_'

-- Snapshot a ped's component variations (drawable/texture/palette per slot).
function CaptureComponents(ped)
	local components = {}

	for i = 0, Config.MpPedComponentSlots do
		local okD, drawable = pcall(GetPedDrawableVariation, ped, i)

		if okD and drawable and drawable >= 0 then
			local okT, texture = pcall(GetPedTextureVariation, ped, i)
			local okP, palette = pcall(GetPedPaletteVariation, ped, i)

			components[tostring(i)] = {
				drawable = drawable,
				texture = (okT and texture) or 0,
				palette = (okP and palette) or 0
			}
		end
	end

	return components
end

-- Re-apply a captured component snapshot to a freshly spawned ped.
function ApplyComponents(ped, components)
	if not components then
		return
	end

	for idxStr, comp in pairs(components) do
		local idx = tonumber(idxStr)

		if idx then
			pcall(SetPedComponentVariation, ped, idx, comp.drawable, comp.texture or 0, comp.palette or 0)
		end
	end
end

-- ===================== Random outfit (shop-item) components =====================
-- Builds and applies an explicit { category = shopItemHash } config using the real
-- clothing hash database in data/rdr3/outfits.lua and ApplyShopItemToPed — this is
-- the actual per-slot mechanism RDR3's own clothing store uses, unlike the black-box
-- SetRandomOutfitVariation/SetPedOutfitPreset natives. The resulting table is plain
-- data (category -> hash), so it can be saved to KVP as-is and re-applied exactly.

-- Layered alternatives, not stackable items — a random outfit keeps at most one
-- from each group (e.g. an open coat should never also get a closed coat or vest
-- piled on top of it).
local OUTERWEAR_GROUP = { 'CoatClosed', 'Coat', 'Vest' }
local NECKWEAR_GROUP = { 'NeckTies', 'NeckWear' }

-- Applies a previously picked/saved { category = hash } config to a ped.
function ApplyOutfitComponents(ped, components)
	if not components then
		return
	end

	for _, hash in pairs(components) do
		pcall(ApplyShopItemToPed, ped, hash)
	end

	UpdatePedVariation(ped)
end

-- Strip the runtime-only template handle before writing to KVP (a ped/entity handle
-- means nothing after a restart) and persist the rest.
function SaveMpPedToKvs(entry)
	local persisted = {
		name = entry.name,
		model = entry.model,
		components = entry.components,
		outfitComponents = entry.outfitComponents,
		weapons = entry.weapons,
		animation = entry.animation,
		scenario = entry.scenario,
		outfit = entry.outfit,
		behavior = entry.behavior,
		weaponInHand = entry.weaponInHand
	}

	if entry.horse then
		persisted.horse = {
			model = entry.horse.model,
			components = entry.horse.components,
			outfitComponents = entry.horse.outfitComponents
		}
	end

	SetResourceKvp(MP_PED_PREFIX .. entry.name, json.encode(persisted))
end

function DeleteMpPedFromKvs(name)
	DeleteResourceKvp(MP_PED_PREFIX .. name)
end

-- Load every persisted MP ped back into SavedMpPeds at resource start. These
-- entries have no `template` (clones don't survive a restart), so spawnMpPed
-- falls back to rebuilding the look from `components`.
function LoadMpPedsFromKvs()
	local handle = StartFindKvp(MP_PED_PREFIX)

	while true do
		local kvp = FindKvp(handle)

		if kvp then
			local content = GetResourceKvpString(kvp)
			local ok, data = pcall(json.decode, content or '')

			if ok and data and data.name then
				SavedMpPeds[data.name] = data
			end
		else
			break
		end
	end

	EndFindKvp(handle)
end

LoadMpPedsFromKvs()

local function CreatePedTemplate(ped)
	local clone = ClonePed(ped, true, true, true)

	if not clone or clone < 1 then
		return nil
	end

	SetEntityAsMissionEntity(clone, true, true)
	SetEntityVisible(clone, false)
	SetEntityCollision(clone, false, false)
	FreezeEntityPosition(clone, true)
	SetEntityInvincible(clone, true)
	ClearPedTasksImmediately(clone)
	SetBlockingOfNonTemporaryEvents(clone, true)

	return clone
end

-- Reset the flags a fresh clone may inherit from the (hidden) template
local function PrepareClone(handle)
	SetEntityVisible(handle, true)
	FreezeEntityPosition(handle, false)
	SetEntityCollision(handle, true, true)
	SetEntityInvincible(handle, false)
	SetBlockingOfNonTemporaryEvents(handle, false)
end

-- Give a weapon and put it in the ped's hand (loading the weapon asset first, or the
-- ped ends up "holding" nothing / the weapon renders in the wrong place).
function EquipWeaponInHand(ped, hash)
	if not hash or hash == 0 or hash == GetHashKey('WEAPON_UNARMED') then
		return
	end

	RequestWeaponAsset(hash, 31, 0)
	local tries = 0
	while not HasWeaponAssetLoaded(hash) and tries < 100 do
		Wait(0)
		tries = tries + 1
	end

	if Config.isRDR then
		GiveWeaponToPed_2(ped, hash, 500, true, false, 0, false, 0.5, 1.0, 0, false, 0.0, false)
	else
		GiveWeaponToPed(ped, hash, 500, false, true)
	end

	SetCurrentPedWeapon(ped, hash, true)
	SetPedCurrentWeaponVisible(ped, true, false, false, false)
end

local function DeleteTemplate(handle)
	if handle and DoesEntityExist(handle) then
		SetEntityAsMissionEntity(handle, true, true)
		DeleteEntity(handle)
	end
end

function GetMpPedNames()
	local names = {}
	for name in pairs(SavedMpPeds) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

function DeleteMpPed(name)
	local entry = SavedMpPeds[name]

	if entry then
		DeleteTemplate(entry.template)
		if entry.horse then
			DeleteTemplate(entry.horse.template)
		end
		SavedMpPeds[name] = nil
	end

	DeleteMpPedFromKvs(name)
end

-- Resource-stop cleanup only: destroys the hidden same-session clone templates so
-- they don't leak. Does NOT touch the KVP-persisted entries — those must survive
-- the restart (unlike DeleteMpPed, which is for an explicit user delete).
function ClearMpPedTemplates()
	for _, entry in pairs(SavedMpPeds) do
		DeleteTemplate(entry.template)
		if entry.horse then
			DeleteTemplate(entry.horse.template)
		end
		entry.template = nil
		if entry.horse then
			entry.horse.template = nil
		end
	end
end

RegisterNUICallback('saveCurrentMpPed', function(data, cb)
	local handle = data.handle
	local name = data.name

	if name and name ~= '' and DoesEntityExist(handle) and GetEntityType(handle) == 1 then
		DeleteMpPed(name) -- replace any existing entry with the same name (memory + disk)

		-- The clone template is a same-session convenience (perfect fidelity, zero
		-- effort); it may fail to create, but that must not block saving. If this ped
		-- was built by "Create Random" (or a previous disk restore), we already know
		-- its exact per-slot shop-item config and can persist that directly — far more
		-- reliable than CaptureComponents, which relies on ped component-variation
		-- natives RDR3 doesn't actually have.
		local template = CreatePedTemplate(handle)
		local db = Database[handle] or {}
		local components = CaptureComponents(handle)
		local outfitComponents = db.outfitComponents

		-- Capture the in-hand weapon safely; these natives may be absent on some
		-- builds and must not abort the whole save if they error.
		local weaponInHand = nil

		local okC, _, curHash = pcall(GetCurrentPedWeapon, handle, true)
		if okC and curHash and curHash ~= 0 then
			weaponInHand = curHash
		end

		if not weaponInHand then
			local okS, selHash = pcall(GetSelectedPedWeapon, handle)
			if okS and selHash and selHash ~= 0 then
				weaponInHand = selHash
			end
		end

		local entry = {
			name = name,
			template = template,
			model = GetEntityModel(handle),
			components = components,
			outfitComponents = outfitComponents,
			weapons = db.weapons or {},
			animation = db.animation,
			scenario = db.scenario,
			outfit = db.outfit or -1,
			behavior = db.behavior,
			weaponInHand = weaponInHand
		}

		-- Save the horse it is riding, if any
		local mount = GetMount(handle)
		if mount and mount ~= 0 and DoesEntityExist(mount) then
			entry.horse = {
				template = CreatePedTemplate(mount),
				model = GetEntityModel(mount),
				components = CaptureComponents(mount)
			}
		end

		SavedMpPeds[name] = entry
		SaveMpPedToKvs(entry)
	end

	cb(json.encode(GetMpPedNames()))
end)

RegisterNUICallback('getMpPeds', function(data, cb)
	cb(json.encode(GetMpPedNames()))
end)

RegisterNUICallback('deleteMpPed', function(data, cb)
	DeleteMpPed(data.name)
	cb({})
end)

RegisterNUICallback('renameMpPed', function(data, cb)
	if data.oldName and data.newName and data.newName ~= '' and data.newName ~= data.oldName then
		local entry = SavedMpPeds[data.oldName]

		if entry then
			entry.name = data.newName
			SavedMpPeds[data.newName] = entry
			SavedMpPeds[data.oldName] = nil

			DeleteMpPedFromKvs(data.oldName)
			SaveMpPedToKvs(entry)
		end
	end

	cb(json.encode(GetMpPedNames()))
end)

-- Spawn one MP ped/horse from a saved entry: uses the exact same-session clone
-- template when it's still alive, otherwise rebuilds the look from the saved
-- component snapshot (the path used after a resource/server restart).
local function SpawnMpPedFromEntry(pedEntry, x, y, z, yaw, extraProps)
	local props = {
		model = ResolveModelHash(pedEntry.model),
		name = GetModelName(pedEntry.model),
		x = x, y = y, z = z,
		pitch = 0.0, roll = 0.0, yaw = yaw,
		collisionDisabled = false,
		isVisible = true,
		outfit = pedEntry.outfit or -1,
		keepAppearance = true,
		isInGroup = false,
		blockNonTemporaryEvents = false
	}

	for k, v in pairs(extraProps or {}) do
		props[k] = v
	end

	if pedEntry.template and DoesEntityExist(pedEntry.template) then
		local clone = ClonePed(pedEntry.template, true, true, true)

		if not clone or clone <= 0 then
			return nil
		end

		PrepareClone(clone)
		props.handle = clone

		return SpawnPed(props)
	end

	-- No live template (e.g. after a restart/rejoin): spawn the base model and
	-- rebuild the look. outfitComponents (per-slot shop-item hashes, built by
	-- "Create Random" or captured at save time) is the reliable path; components
	-- (old drawable/texture snapshot) is kept only as a last-resort fallback for
	-- entries saved before this existed — it's a no-op on RDR3 in practice.
	local ped = SpawnPed(props)

	if ped then
		WaitForPedReadyToRender(ped)

		if pedEntry.outfitComponents and next(pedEntry.outfitComponents) then
			ApplyOutfitComponents(ped, pedEntry.outfitComponents)
		else
			ApplyComponents(ped, pedEntry.components)
			UpdatePedVariation(ped)
		end

		SetEntityVisible(ped, true)
		Database[ped].outfitComponents = pedEntry.outfitComponents
	end

	return ped
end

RegisterNUICallback('spawnMpPed', function(data, cb)
	ClearPreview()

	local entry = SavedMpPeds[data.name]

	if entry then
		local x, y, z = table.unpack(GetCamCoord(Cam))
		local pitch, roll, yaw = table.unpack(GetCamRot(Cam, 2))
		local spawnPos = GetInView(x, y, z, pitch, roll, yaw)

		local yaw2 = yaw
		if yaw2 < 0.0 then
			yaw2 = yaw2 + 360.0
		end

		local ped = SpawnMpPedFromEntry(entry, spawnPos.x, spawnPos.y, spawnPos.z, yaw2, {
			animation = entry.animation,
			scenario = entry.scenario,
			weapons = entry.weapons
		})

		if ped and entry.behavior and Database[ped] then
			Database[ped].behavior = entry.behavior
		end

		-- Put the ped's in-hand weapon (e.g. lasso) back into its hand; cloning keeps
		-- it holstered, so it looks missing / ends up in the wrong place.
		if ped and entry.weaponInHand and entry.weaponInHand ~= 0 and entry.weaponInHand ~= GetHashKey('WEAPON_UNARMED') then
			EquipWeaponInHand(ped, entry.weaponInHand)
		end

		local grabTarget = ped
		local grabNoFreeze = false

		-- Re-spawn the horse and put the ped on it
		if ped and entry.horse then
			local horse = SpawnMpPedFromEntry(entry.horse, spawnPos.x, spawnPos.y, spawnPos.z, yaw2)

			if horse then
				PlaceOnGroundProperly(horse)

				-- The lasso in RDR2 lives on the horse (saddle rope). The clone/rebuild
				-- carries it, so it dangles under the horse. The rider already holds his
				-- own, so strip the horse's weapons to remove the extra rope.
				RemoveAllPedWeapons(horse, true)

				-- Let both fully stream in, then seat the rider. Mounting a
				-- just-created horse in the same frame leaves the rider standing
				-- in a T-pose at the horse's centre.
				Wait(300)
				SetPedOnMount(ped, horse, -1, false)

				-- Grab the HORSE so the pair can still be positioned, but WITHOUT
				-- freezing it (freezing dismounts the rider into a T-pose).
				grabTarget = horse
				grabNoFreeze = true
			end
		end

		if ped then
			CurrentSpawn = nil
			PlaceOnGroundProperly(grabTarget)
			GrabNoFreeze = grabNoFreeze
			TriggerEvent('spooner:onEntityUnselected', AttachedEntity)
			AttachedEntity = grabTarget
			TriggerEvent('spooner:onEntitySelected', AttachedEntity)
		end
	end

	SetNuiFocus(false, false)
	cb({})
end)

-- Spawns a bare mp_male/mp_female ped in view of the camera, with no outfit applied
-- yet (keepAppearance = true so SpawnPed's own outfit logic doesn't touch it) —
-- used by the "Create Custom" manual editor below.
local function SpawnBareMpPed(gender)
	local model = gender == 'female' and 'mp_female' or 'mp_male'
	local hash = ResolveModelHash(model)

	if not LoadModel(hash) then
		return nil
	end

	local x, y, z = table.unpack(GetCamCoord(Cam))
	local pitch, roll, yaw = table.unpack(GetCamRot(Cam, 2))
	local spawnPos = GetInView(x, y, z, pitch, roll, yaw)

	local yaw2 = yaw
	if yaw2 < 0.0 then
		yaw2 = yaw2 + 360.0
	end

	local ped = SpawnPed({
		model = hash,
		name = model,
		x = spawnPos.x, y = spawnPos.y, z = spawnPos.z,
		pitch = 0.0, roll = 0.0, yaw = yaw2,
		collisionDisabled = false,
		isVisible = true,
		keepAppearance = true, -- we drive the outfit ourselves, in the right order
		isInGroup = false,
		blockNonTemporaryEvents = false
	})

	if ped then
		WaitForPedReadyToRender(ped)
	end

	return ped
end

local function SelectSpawnedMpPed(ped)
	CurrentSpawn = nil
	PlaceOnGroundProperly(ped)
	TriggerEvent('spooner:onEntityUnselected', AttachedEntity)
	AttachedEntity = ped
	TriggerEvent('spooner:onEntitySelected', AttachedEntity)
end

-- ===================== Custom Ped editor (manual per-slot picker) =====================
-- Same component config format as "Create Random" (category -> shop-item hash),
-- but built by hand: every category is exposed as a cyclable option (prev/next, or
-- typing an index directly), plus "None" for anything but the required base slots,
-- so the player can assemble any exact combination themselves.
--
-- Heads/BodiesUpper/BodiesLower are NOT plain option lists like clothing — RDR3's
-- skin-tone groups use different index ranges per part (e.g. "black" is head index
-- 21 but body/legs index 6), so cycling them independently produces mismatched skin
-- tones between face and body. Skin Tone is its own row that picks the tone group;
-- Head/Body/Legs Shape pick which template *within* that group, so tone always
-- stays in sync across all three.

local CUSTOM_BODY_ROW_FIELD = {
	SkinTone = 'tone',
	HeadShape = 'headShape',
	BodyShape = 'bodyShape',
	LegsShape = 'legsShape'
}

local CUSTOM_BODY_ROW_ORDER = { 'SkinTone', 'HeadShape', 'BodyShape', 'LegsShape' }

local CUSTOM_CATEGORY_ORDER = {
	'Hair', 'Beard', 'Eyes', 'Teeth',
	'Shirt', 'Pant', 'Skirt', 'Dress', 'Boots', 'Belt', 'Suspender', 'Vest',
	'Coat', 'CoatClosed', 'Poncho', 'Cloak', 'Hat', 'Glove', 'Gauntlets',
	'EyeWear', 'Mask', 'NeckTies', 'NeckWear', 'Bracelet', 'RingLh', 'RingRh',
	'Buckle', 'Spurs', 'Chap', 'Spats', 'Armor', 'Badge', 'Satchels', 'Holster',
	'Gunbelt', 'gunbelt_accs', 'Accessories'
}

-- Categories where the *equipped item itself* can have more than one worn position
-- (RDR3 "wearable states") — e.g. a bandana/neckerchief pulled down vs up over the
-- face. Only NeckWear gets the extra toggle button; Hat/Mask/NeckTies were tried
-- too but didn't produce a reliably useful look, so they were dropped.
local CUSTOM_WEARABLE_STATE_CATEGORIES = {
	NeckWear = true
}

-- Found by testing in-game: most wearable-state indices for a given item are either
-- indistinguishable or broken-looking — these are the only ones actually worth
-- cycling through via the toggle button. 0 is NeckWear's default/initial state, so
-- it can be toggled back down, not just up.
local CUSTOM_WEARABLE_STATE_ALLOWED = {
	NeckWear = { 0, 5, 6, 7 }
}

-- Categories that always have something equipped (no "None" option).
local CUSTOM_REQUIRED_CATEGORIES = {
	Eyes = true, Teeth = true
}

-- Optional categories that still start with something equipped (rather than "None")
-- so the ped isn't naked the moment the editor opens.
local CUSTOM_DEFAULT_DRESSED = {
	Shirt = true, Pant = true, Boots = true, Hair = true
}

local function GetBodyRowCount(session, row)
	local tone = PedBodyData and PedBodyData[session.tone]

	if row == 'SkinTone' then
		return #(PedBodyData or {})
	elseif row == 'HeadShape' then
		return tone and #tone.heads or 0
	elseif row == 'BodyShape' then
		return tone and #tone.bodies or 0
	elseif row == 'LegsShape' then
		return tone and #tone.legs or 0
	end

	return 0
end

-- Re-applies Heads/BodiesUpper/BodiesLower from the session's current tone + shape
-- indices. Called any time tone OR any of the three shapes changes, since a tone
-- change has to cascade to all three to keep them matching.
local function ApplyBodyAppearance(session)
	local tone = PedBodyData and PedBodyData[session.tone]

	if not tone then
		return
	end

	local genderLetter = session.gender == 'female' and 'F' or 'M'

	local headTemplate = tone.heads[session.headShape]
	local bodyTemplate = tone.bodies[session.bodyShape]
	local legsTemplate = tone.legs[session.legsShape]

	if headTemplate then
		pcall(ApplyShopItemToPed, session.ped, GetHashKey(string.format(headTemplate, genderLetter)))
	end

	if bodyTemplate then
		pcall(ApplyShopItemToPed, session.ped, GetHashKey(string.format(bodyTemplate, genderLetter)))
	end

	if legsTemplate then
		pcall(ApplyShopItemToPed, session.ped, GetHashKey(string.format(legsTemplate, genderLetter)))
	end
end

local function FlattenCustomCategoryOptions(category, gender, genderLetter)
	local options = {}

	if category == 'Eyes' then
		for _, template in ipairs(PedEyeData or {}) do
			table.insert(options, GetHashKey(string.format(template, genderLetter)))
		end
	elseif category == 'Teeth' then
		for _, template in ipairs(PedTeethData or {}) do
			table.insert(options, GetHashKey(string.format(template, genderLetter)))
		end
	elseif category == 'Hair' then
		for _, group in ipairs((PedHairData and PedHairData[gender]) or {}) do
			for _, variant in ipairs(group) do
				table.insert(options, variant.hash)
			end
		end
	elseif category == 'Beard' then
		-- Male only; PedBeardData is a flat group list (no gender wrapper) since
		-- there's no female equivalent in this dataset.
		if gender == 'male' then
			for _, group in ipairs(PedBeardData or {}) do
				for _, variant in ipairs(group) do
					table.insert(options, variant.hash)
				end
			end
		end
	else
		local groups = PedOutfitData and PedOutfitData[gender] and PedOutfitData[gender][category]

		for _, group in ipairs(groups or {}) do
			for _, variant in ipairs(group) do
				table.insert(options, variant.hash)
			end
		end
	end

	return options
end

-- Builds the ordered category list for a fresh editor session: each entry is
-- { category, options = {hash, ...}, index (0 = None), required, appliedHash }.
-- `list` preserves display order; `byName` points at the same entry tables for
-- O(1) lookup when a cycle/set-index request comes in from the UI.
local function BuildCustomCategories(gender)
	local genderLetter = gender == 'female' and 'F' or 'M'
	local seen = {}
	local order = {}

	for _, category in ipairs(CUSTOM_CATEGORY_ORDER) do
		seen[category] = true
		table.insert(order, category)
	end

	if PedOutfitData and PedOutfitData[gender] then
		local extra = {}

		for category in pairs(PedOutfitData[gender]) do
			if not seen[category] then
				table.insert(extra, category)
			end
		end

		table.sort(extra)

		for _, category in ipairs(extra) do
			table.insert(order, category)
		end
	end

	local list = {}
	local byName = {}

	for _, category in ipairs(order) do
		local options = FlattenCustomCategoryOptions(category, gender, genderLetter)

		if #options > 0 then
			local required = CUSTOM_REQUIRED_CATEGORIES[category] or false
			local index = (required or CUSTOM_DEFAULT_DRESSED[category]) and math.random(#options) or 0

			local entry = { category = category, options = options, index = index, required = required }

			table.insert(list, entry)
			byName[category] = entry
		end
	end

	return list, byName
end

-- (Re)applies every entry's current pick to the session's ped. Applying a new shop
-- item to a category replaces whatever was in that slot already — RemoveShopItemFromPed
-- is only needed to actually clear a slot down to "None". This matters here (unlike
-- a single manual cycle) because a re-randomize can flip an already-equipped slot
-- (e.g. a coat) back to "None" — without removing it, the old item stays stuck on
-- the ped even though the session no longer thinks it's equipped.
local function ApplyCustomPedComponents(session)
	for _, entry in ipairs(session.list) do
		if entry.index > 0 then
			local hash = entry.options[entry.index]
			pcall(ApplyShopItemToPed, session.ped, hash)
			entry.appliedHash = hash
			entry.wearableStateIndex = 0
		else
			if entry.appliedHash then
				pcall(RemoveShopItemFromPed, session.ped, entry.appliedHash)
			end
			entry.appliedHash = nil
			entry.wearableStateIndex = nil
		end
	end

	UpdatePedVariation(session.ped)
end

local function GetCustomPedComponents(session)
	local components = {}

	local tone = PedBodyData and PedBodyData[session.tone]

	if tone then
		local genderLetter = session.gender == 'female' and 'F' or 'M'
		local headTemplate = tone.heads[session.headShape]
		local bodyTemplate = tone.bodies[session.bodyShape]
		local legsTemplate = tone.legs[session.legsShape]

		if headTemplate then
			components.Heads = GetHashKey(string.format(headTemplate, genderLetter))
		end

		if bodyTemplate then
			components.BodiesUpper = GetHashKey(string.format(bodyTemplate, genderLetter))
		end

		if legsTemplate then
			components.BodiesLower = GetHashKey(string.format(legsTemplate, genderLetter))
		end
	end

	for _, entry in ipairs(session.list) do
		if entry.appliedHash then
			components[entry.category] = entry.appliedHash
		end
	end

	return components
end

local function SerializeCustomCategories(session)
	local rows = {}

	for _, row in ipairs(CUSTOM_BODY_ROW_ORDER) do
		table.insert(rows, {
			category = row,
			index = session[CUSTOM_BODY_ROW_FIELD[row]],
			count = GetBodyRowCount(session, row),
			required = true
		})
	end

	for _, entry in ipairs(session.list) do
		table.insert(rows, {
			category = entry.category,
			index = entry.index,
			count = #entry.options,
			required = entry.required,
			hasState = CUSTOM_WEARABLE_STATE_CATEGORIES[entry.category] or false
		})
	end

	return rows
end

-- Cycles the currently-equipped item in `category` to its next wearable state, but
-- only among the curated CUSTOM_WEARABLE_STATE_ALLOWED indices for that category
-- (not every state the item has — most of those are indistinguishable or broken).
-- No-ops if the item doesn't actually have that many states, or the slot is empty.
local function CycleWearableState(session, category)
	local entry = session.byName[category]
	local allowed = CUSTOM_WEARABLE_STATE_ALLOWED[category]

	if not entry or not entry.appliedHash or not allowed or #allowed == 0 then
		return 0, 0
	end

	local isMpFemale = session.gender == 'female'
	local okCount, count = pcall(GetShopItemNumWearableStates, entry.appliedHash, isMpFemale)

	if not okCount or not count or count <= 1 then
		return 0, (okCount and count) or 0
	end

	-- Clamp (rather than drop) indices past what this specific item actually has —
	-- different items in the same category can have different state counts, and
	-- silently excluding an out-of-range index could leave the whole allowed list
	-- empty, making the button do nothing at all for that item.
	local validAllowed = {}
	local seen = {}

	for _, idx in ipairs(allowed) do
		local clamped = math.min(idx, count - 1)

		if not seen[clamped] then
			seen[clamped] = true
			table.insert(validAllowed, clamped)
		end
	end

	if #validAllowed == 0 then
		return 0, count
	end

	local currentPos = nil

	for i, idx in ipairs(validAllowed) do
		if idx == entry.wearableStateIndex then
			currentPos = i
			break
		end
	end

	local nextPos = currentPos and (currentPos % #validAllowed) + 1 or 1
	local nextIndex = validAllowed[nextPos]

	entry.wearableStateIndex = nextIndex

	local okState, stateHash = pcall(GetShopItemWearableStateByIndex, entry.appliedHash, nextIndex, isMpFemale)

	if okState and stateHash then
		pcall(UpdateShopItemWearableState, session.ped, entry.appliedHash, stateHash, true)
		UpdatePedVariation(session.ped)
	end

	return entry.wearableStateIndex, count
end

RegisterNUICallback('customPedToggleWearableState', function(data, cb)
	local session = CustomPedSession

	if session and session.ped and DoesEntityExist(session.ped) then
		local stateIndex, stateCount = CycleWearableState(session, data.category)
		cb(json.encode({ stateIndex = stateIndex, stateCount = stateCount }))
		return
	end

	cb(json.encode({}))
end)

-- Picks a random skin tone + head/body/legs shape within it (all in sync, see
-- ApplyBodyAppearance).
local function RandomizeCustomBodyAppearance(session)
	if not (PedBodyData and #PedBodyData > 0) then
		return
	end

	session.tone = math.random(#PedBodyData)

	local tone = PedBodyData[session.tone]

	session.headShape = math.random(#tone.heads)
	session.bodyShape = math.random(#tone.bodies)
	session.legsShape = math.random(#tone.legs)
end

-- Randomizes session.list the same way "Create Random" does (Config.RandomOutfitChance
-- + Config.RandomBeardChance + the Coat/CoatClosed/Vest and NeckTies/NeckWear
-- exclusivity groups) — most categories end up "None", not every accessory equipped
-- at once.
local function RandomizeCustomList(session)
	local byName = session.byName

	local function pick(category, forceOn)
		local entry = byName[category]

		if not entry then
			return
		end

		if forceOn then
			entry.index = math.random(#entry.options)
			return
		end

		local chance = Config.RandomOutfitChance[category]
		entry.index = (chance and math.random() <= chance) and math.random(#entry.options) or 0
	end

	for _, entry in ipairs(session.list) do
		entry.index = 0
	end

	pick('Pant', true)
	pick('Skirt', true)
	pick('Shirt', true)
	pick('Boots', true)
	pick('Hair', true)
	pick('Eyes', true)
	pick('Teeth', true)

	local beardEntry = byName.Beard
	if beardEntry and math.random() <= (Config.RandomBeardChance or 0) then
		pick('Beard', true)
	end

	for category in pairs(Config.RandomOutfitChance) do
		pick(category, false)
	end

	for _, group in ipairs({ OUTERWEAR_GROUP, NECKWEAR_GROUP }) do
		local kept = nil

		for _, category in ipairs(group) do
			local entry = byName[category]

			if entry and entry.index > 0 then
				if kept then
					entry.index = 0
				else
					kept = category
				end
			end
		end
	end
end

-- Spawns a brand-new temp ped to edit (MP Peds -> Create Custom). Only ever deletes
-- a *previous temp* ped on re-entry — never touches a ped handed in via
-- StartCustomizeSession (Ped Options -> Customize), which is a real, already-placed
-- entity the player owns and must not get deleted out from under them.
local function StartCustomPedSession(gender)
	if CustomPedSession and CustomPedSession.isTemp and CustomPedSession.ped and DoesEntityExist(CustomPedSession.ped) then
		RemoveEntity(CustomPedSession.ped)
	end

	CustomPedSession = nil

	local ped = SpawnBareMpPed(gender)

	if not ped then
		return nil
	end

	local list, byName = BuildCustomCategories(gender)

	CustomPedSession = {
		ped = ped, gender = gender, list = list, byName = byName,
		tone = 1, headShape = 1, bodyShape = 1, legsShape = 1,
		isTemp = true
	}

	RandomizeCustomBodyAppearance(CustomPedSession)
	ApplyBodyAppearance(CustomPedSession)
	ApplyCustomPedComponents(CustomPedSession)
	SetEntityVisible(ped, true)

	Database[ped].outfitComponents = GetCustomPedComponents(CustomPedSession)

	SelectSpawnedMpPed(ped)

	return CustomPedSession
end

-- If we already know exactly what's applied to this ped (Database[ped].outfitComponents,
-- tracked ever since it was built by Create Random/Create Custom, or restored from a
-- saved MP ped), reverse-map those known hashes back to row indices so the editor
-- reflects reality instead of starting blank. Peds we have no record for (an
-- ordinary NPC, the player, anything not created through this system) simply don't
-- match anything and every row falls back to its blank starting position.
local function HydrateCustomSessionFromComponents(session, components)
	local genderLetter = session.gender == 'female' and 'F' or 'M'

	if PedBodyData and (components.Heads or components.BodiesUpper or components.BodiesLower) then
		for toneIndex, tone in ipairs(PedBodyData) do
			local matchedTone = false

			if components.Heads then
				for shapeIndex, template in ipairs(tone.heads) do
					if GetHashKey(string.format(template, genderLetter)) == components.Heads then
						session.tone = toneIndex
						session.headShape = shapeIndex
						matchedTone = true
						break
					end
				end
			end

			if matchedTone then
				if components.BodiesUpper then
					for shapeIndex, template in ipairs(tone.bodies) do
						if GetHashKey(string.format(template, genderLetter)) == components.BodiesUpper then
							session.bodyShape = shapeIndex
							break
						end
					end
				end

				if components.BodiesLower then
					for shapeIndex, template in ipairs(tone.legs) do
						if GetHashKey(string.format(template, genderLetter)) == components.BodiesLower then
							session.legsShape = shapeIndex
							break
						end
					end
				end

				break
			end
		end
	end

	for _, entry in ipairs(session.list) do
		local hash = components[entry.category]

		if hash then
			for optIndex, optHash in ipairs(entry.options) do
				if optHash == hash then
					entry.index = optIndex
					entry.appliedHash = hash
					entry.wearableStateIndex = 0
					break
				end
			end
		end
	end
end

-- Opens the same editor on a ped that already exists in the world (Properties ->
-- Ped Options -> Customize) instead of spawning a fresh one. If this ped was built
-- by our own system (Create Random/Create Custom/a saved MP ped), its exact look is
-- already known (Database[ped].outfitComponents) and gets restored into the editor
-- via HydrateCustomSessionFromComponents. Otherwise (an ordinary NPC, the player,
-- anything we have no record for) there's no reliable way to read back what's
-- equipped, so every row starts blank — the ped's current look is left untouched
-- either way; nothing is applied here, only once the player interacts with a row.
local function StartCustomizeSession(ped, gender)
	-- Only clean up a *different, stale* temp ped left over from a previous Create
	-- Custom session — if the ped being customized now happens to be that same temp
	-- ped (e.g. it was left in the world and later re-selected), it must not be
	-- deleted out from under the very session that's about to edit it.
	if CustomPedSession and CustomPedSession.isTemp and CustomPedSession.ped and CustomPedSession.ped ~= ped and DoesEntityExist(CustomPedSession.ped) then
		RemoveEntity(CustomPedSession.ped)
	end

	local list, byName = BuildCustomCategories(gender)

	for _, entry in ipairs(list) do
		if not entry.required then
			entry.index = 0
		end
	end

	local session = {
		ped = ped, gender = gender, list = list, byName = byName,
		tone = 1, headShape = 1, bodyShape = 1, legsShape = 1,
		isTemp = false
	}

	local knownComponents = Database[ped] and Database[ped].outfitComponents

	if knownComponents and next(knownComponents) then
		HydrateCustomSessionFromComponents(session, knownComponents)
	end

	CustomPedSession = session

	Database[ped] = Database[ped] or {}
	Database[ped].outfitComponents = Database[ped].outfitComponents or {}

	return CustomPedSession
end

RegisterNUICallback('openCustomMpPed', function(data, cb)
	local session = nil

	if Permissions.spawn.ped then
		local gender = data.gender == 'female' and 'female' or 'male'
		session = StartCustomPedSession(gender)
	end

	if session then
		cb(json.encode({ gender = session.gender, genderLocked = false, handle = session.ped, categories = SerializeCustomCategories(session) }))
	else
		cb(json.encode({}))
	end
end)

-- Ped Options -> Customize: edit the selected, already-existing ped in place.
RegisterNUICallback('openCustomizePed', function(data, cb)
	local ped = tonumber(data.handle)
	local session = nil

	if Permissions.spawn.ped and ped and DoesEntityExist(ped) and GetEntityType(ped) == 1 then
		local model = GetEntityModel(ped)
		local gender = (model == GetHashKey('mp_female')) and 'female' or 'male'
		session = StartCustomizeSession(ped, gender)
	end

	if session then
		cb(json.encode({ gender = session.gender, genderLocked = true, handle = session.ped, categories = SerializeCustomCategories(session) }))
	else
		cb(json.encode({}))
	end
end)

RegisterNUICallback('customPedSetGender', function(data, cb)
	local session = nil

	-- Switching gender means spawning a different model, which only makes sense
	-- for the temp "Create Custom" ped — never for an existing ped being customized.
	if Permissions.spawn.ped and (not CustomPedSession or CustomPedSession.isTemp) then
		local gender = data.gender == 'female' and 'female' or 'male'
		session = StartCustomPedSession(gender)
	end

	if session then
		cb(json.encode({ gender = session.gender, genderLocked = false, handle = session.ped, categories = SerializeCustomCategories(session) }))
	else
		cb(json.encode({}))
	end
end)

-- Shared by customPedCycle (relative) and customPedSetIndex (absolute): moves the
-- given row to newIndex (already clamped/wrapped by the caller) and re-applies it.
local function SetCustomRowIndex(session, category, newIndex)
	if CUSTOM_BODY_ROW_FIELD[category] then
		session[CUSTOM_BODY_ROW_FIELD[category]] = newIndex
		ApplyBodyAppearance(session)
		UpdatePedVariation(session.ped)

		Database[session.ped].outfitComponents = GetCustomPedComponents(session)

		return newIndex, GetBodyRowCount(session, category)
	end

	local entry = session.byName[category]

	if not entry then
		return nil
	end

	entry.index = newIndex

	if newIndex == 0 then
		if entry.appliedHash then
			pcall(RemoveShopItemFromPed, session.ped, entry.appliedHash)
			entry.appliedHash = nil
		end
		entry.wearableStateIndex = nil
	else
		local hash = entry.options[newIndex]
		pcall(ApplyShopItemToPed, session.ped, hash)
		entry.appliedHash = hash
		entry.wearableStateIndex = 0
	end

	UpdatePedVariation(session.ped)

	Database[session.ped].outfitComponents = GetCustomPedComponents(session)

	return newIndex, #entry.options
end

local function GetCustomRowState(session, category)
	if CUSTOM_BODY_ROW_FIELD[category] then
		return session[CUSTOM_BODY_ROW_FIELD[category]] or 1, GetBodyRowCount(session, category), true
	end

	local entry = session.byName[category]

	if not entry then
		return nil
	end

	return entry.index, #entry.options, entry.required
end

RegisterNUICallback('customPedCycle', function(data, cb)
	local session = CustomPedSession

	if session and session.ped and DoesEntityExist(session.ped) then
		local index, count, required = GetCustomRowState(session, data.category)

		if index then
			local minIndex = required and 1 or 0
			local direction = (data.direction == -1) and -1 or 1
			local newIndex = index + direction

			if newIndex > count then
				newIndex = minIndex
			elseif newIndex < minIndex then
				newIndex = count
			end

			local finalIndex, finalCount = SetCustomRowIndex(session, data.category, newIndex)

			cb(json.encode({ index = finalIndex, count = finalCount }))
			return
		end
	end

	cb(json.encode({}))
end)

-- Lets the player type an exact option number, or jump straight to "None" (0) via
-- the dedicated clear button — both go through the same clamp-and-apply path.
RegisterNUICallback('customPedSetIndex', function(data, cb)
	local session = CustomPedSession

	if session and session.ped and DoesEntityExist(session.ped) then
		local index, count, required = GetCustomRowState(session, data.category)

		if index then
			local minIndex = required and 1 or 0
			local requested = math.floor(tonumber(data.index) or 0)
			local newIndex = math.max(minIndex, math.min(count, requested))

			local finalIndex, finalCount = SetCustomRowIndex(session, data.category, newIndex)

			cb(json.encode({ index = finalIndex, count = finalCount }))
			return
		end
	end

	cb(json.encode({}))
end)

RegisterNUICallback('customPedRandomizeAll', function(data, cb)
	local session = CustomPedSession

	if session and session.ped and DoesEntityExist(session.ped) then
		RandomizeCustomBodyAppearance(session)
		RandomizeCustomList(session)

		ApplyBodyAppearance(session)
		ApplyCustomPedComponents(session)
		SetEntityVisible(session.ped, true)

		Database[session.ped].outfitComponents = GetCustomPedComponents(session)

		cb(json.encode({ gender = session.gender, genderLocked = not session.isTemp, handle = session.ped, categories = SerializeCustomCategories(session) }))
		return
	end

	cb(json.encode({}))
end)

RegisterNUICallback('closeCustomMpPed', function(data, cb)
	-- Once the editor is closed, its ped is "placed" like any other spawned ped —
	-- clear the session so a later Create Custom doesn't treat it as a leftover
	-- disposable draft and delete it out from under the player.
	CustomPedSession = nil

	SetNuiFocus(false, false)
	cb({})
end)

-- ===================== Saved Animation + Prop presets =====================
-- Captures a ped's current animation and its first attached prop as one reusable
-- preset (persisted to disk), so it can be applied later to any other ped: play
-- the animation and re-spawn+attach the same prop with the same bone/offset.

local ANIMPROP_PREFIX = 'ANIMPROP_'

SavedAnimProps = SavedAnimProps or {}

-- In-session clipboard filled by "Copy Animation + Prop"; "Save" persists whatever
-- is currently held here under a name.
local CopiedAnimationProp = nil

function SaveAnimPropToKvs(entry)
	SetResourceKvp(ANIMPROP_PREFIX .. entry.name, json.encode(entry))
end

function DeleteAnimPropFromKvs(name)
	DeleteResourceKvp(ANIMPROP_PREFIX .. name)
end

function LoadAnimPropsFromKvs()
	local handle = StartFindKvp(ANIMPROP_PREFIX)

	while true do
		local kvp = FindKvp(handle)

		if kvp then
			local content = GetResourceKvpString(kvp)
			local ok, data = pcall(json.decode, content or '')

			if ok and data and data.name then
				SavedAnimProps[data.name] = data
			end
		else
			break
		end
	end

	EndFindKvp(handle)
end

LoadAnimPropsFromKvs()

function GetAnimPropNames()
	local names = {}
	for name in pairs(SavedAnimProps) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

function DeleteAnimProp(name)
	SavedAnimProps[name] = nil
	DeleteAnimPropFromKvs(name)
end

RegisterNUICallback('copyAnimationProp', function(data, cb)
	local entity = data.handle

	local anim = GetAnimationInfo(entity)
	if not anim and Database[entity] then
		anim = Database[entity].animation
	end

	-- Capture every prop currently attached to the ped, not just one.
	local props = {}

	for _, child in ipairs(GetAttachedChildren(entity)) do
		local cdb = Database[child]

		if cdb then
			local a = cdb.attachment

			table.insert(props, {
				name = cdb.name,
				model = cdb.model,
				attachment = {
					bone = a.bone,
					x = a.x, y = a.y, z = a.z,
					pitch = a.pitch, roll = a.roll, yaw = a.yaw,
					useSoftPinning = a.useSoftPinning,
					collision = a.collision,
					vertex = a.vertex,
					fixedRot = a.fixedRot
				}
			})
		end
	end

	if anim or #props > 0 then
		CopiedAnimationProp = {
			animation = anim,
			props = props
		}

		cb({ ok = true, hasAnimation = anim ~= nil, propCount = #props })
	else
		CopiedAnimationProp = nil
		cb({ ok = false })
	end
end)

RegisterNUICallback('saveAnimationProp', function(data, cb)
	if data.name and data.name ~= '' and CopiedAnimationProp then
		local entry = {
			name = data.name,
			animation = CopiedAnimationProp.animation,
			props = CopiedAnimationProp.props
		}

		SavedAnimProps[data.name] = entry
		SaveAnimPropToKvs(entry)
	end

	cb(json.encode(GetAnimPropNames()))
end)

RegisterNUICallback('getAnimProps', function(data, cb)
	cb(json.encode(GetAnimPropNames()))
end)

RegisterNUICallback('deleteAnimProp', function(data, cb)
	DeleteAnimProp(data.name)
	cb({})
end)

RegisterNUICallback('renameAnimProp', function(data, cb)
	if data.oldName and data.newName and data.newName ~= '' and data.newName ~= data.oldName then
		local entry = SavedAnimProps[data.oldName]

		if entry then
			entry.name = data.newName
			SavedAnimProps[data.newName] = entry
			SavedAnimProps[data.oldName] = nil

			DeleteAnimPropFromKvs(data.oldName)
			SaveAnimPropToKvs(entry)
		end
	end

	cb(json.encode(GetAnimPropNames()))
end)

RegisterNUICallback('applyAnimProp', function(data, cb)
	local entity = data.handle
	local entry = SavedAnimProps[data.name]

	if entry and DoesEntityExist(entity) and CanModifyEntity(entity) then
		RequestControl(entity)

		if entry.animation and Permissions.properties.ped.animation then
			if PlayAnimation(entity, entry.animation) and Database[entity] then
				Database[entity].animation = entry.animation
				Database[entity].scenario = nil
			end
			StoreAnimationInfo(entity, entry.animation)
		end

		-- Support both the new multi-prop format (entry.props, an array) and the
		-- older single-prop format (entry.prop) from before this saved more than one.
		local propsList = entry.props
		if (not propsList or #propsList == 0) and entry.prop then
			propsList = { entry.prop }
		end

		if propsList and Permissions.spawn.object and Permissions.properties.attachments then
			local x, y, z = table.unpack(GetEntityCoords(entity))

			for _, propEntry in ipairs(propsList) do
				local child = SpawnObject(propEntry.name, ResolveModelHash(propEntry.model), x, y, z, 0.0, 0.0, 0.0, false, true)

				if child then
					local a = propEntry.attachment
					AttachEntity(child, entity, a.bone, a.x, a.y, a.z, a.pitch, a.roll, a.yaw, a.useSoftPinning, a.collision, a.vertex, a.fixedRot)
				end
			end
		end
	end

	cb({})
end)

