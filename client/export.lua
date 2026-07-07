-- ============================================================================
-- spooner :: client/export.lua
-- Database import/export (MapEditor XML, YMAP, PropPlacer JSON), backup/restore
--
-- Part of the split client.lua. All spooner client modules share one Lua state
-- and _G, so globals defined in any module are visible to the others.
-- ============================================================================

function ConvertDatabaseToMapEditorXml(creator, database)
	local xml = '<?xml version="1.0"?>\n<Map>\n\t<MapMeta Creator="' .. creator .. '"/>\n'

	for _, properties in ipairs(database.delete) do
		xml = xml .. string.format('\t<DeletedObject Hash="%s" Position_x="%s" Position_y="%s" Position_z="%s"/>\n', properties.model, properties.x, properties.y, properties.z)
	end

	for entity, properties in pairs(database.spawn) do
		if properties.type == 1 then
			xml = xml .. string.format('\t<Ped Hash="%s" Position_x="%s" Position_y="%s" Position_z="%s" Rotation_x="%s" Rotation_y="%s" Rotation_z="%s" Preset="%d" Collision="%s" Visible="%s"/>\n', properties.model, properties.x, properties.y, properties.z, properties.pitch, properties.roll, properties.yaw, properties.outfit, properties.collisionDisabled and "false" or "true", properties.isVisible and "true" or "false")
		elseif properties.type == 2 then
			xml = xml .. string.format('\t<Vehicle Hash="%s" Position_x="%s" Position_y="%s" Position_z="%s" Rotation_x="%s" Rotation_y="%s" Rotation_z="%s" Collision="%s" Visible="%s"/>\n', properties.model, properties.x, properties.y, properties.z, properties.pitch, properties.roll, properties.yaw, properties.collisionDisabled and "false" or "true", properties.isVisible and "true" or "false")
		else
			xml = xml .. string.format('\t<Object Hash="%s" Position_x="%s" Position_y="%s" Position_z="%s" Rotation_x="%s" Rotation_y="%s" Rotation_z="%s" Collision="%s" Visible="%s"/>\n', properties.model, properties.x, properties.y, properties.z, properties.pitch, properties.roll, properties.yaw, properties.collisionDisabled and "false" or "true", properties.isVisible and "true" or "false")
		end
	end

	xml = xml .. '</Map>'

	return xml
end

local function toQuaternion(pitch, roll, yaw)
	local rot = -vector3(roll, pitch, yaw)

	local p = math.rad(rot.y)
	local r = math.rad(rot.z)
	local y = math.rad(rot.x)

	local cy = math.cos(y * 0.5)
	local sy = math.sin(y * 0.5)
	local cr = math.cos(r * 0.5)
	local sr = math.sin(r * 0.5)
	local cp = math.cos(p * 0.5)
	local sp = math.sin(p * 0.5)

	local q = {}

	q.x = cy * sp * cr + sy * cp * sr
	q.y = sy * cp * cr - cy * sp * sr
	q.z = cy * cp * sr - sy * sp * cr
	q.w = cy * cp * cr + sy * sp * sr

	return q
end

function ConvertDatabaseToYmap(database)
	local minX, maxX, minY, maxY, minZ, maxZ

	local entitiesXml = '\t<entities>\n'

	for entity, properties in pairs(database.spawn) do
		if properties.type == 3 then
			local q = toQuaternion(properties.pitch, properties.roll, properties.yaw)

			if not minX or properties.x < minX then
				minX = properties.x
			end
			if not maxX or properties.x > maxX then
				maxX = properties.x
			end
			if not minY or properties.y < minY then
				minY = properties.y
			end
			if not maxY or properties.y > maxY then
				maxY = properties.y
			end
			if not minZ or properties.z < minZ then
				minZ = properties.z
			end
			if not maxZ or properties.z > maxZ then
				maxZ = properties.z
			end

			local flags = 1572865

			if properties.isFrozen then
				flags = flags + 32
			end

			entitiesXml = entitiesXml .. '\t\t<Item type="CEntityDef">\n'
			entitiesXml = entitiesXml .. '\t\t\t<archetypeName>' .. properties.name .. '</archetypeName>\n'
			entitiesXml = entitiesXml .. '\t\t\t<flags value="' .. flags .. '"/>\n'
			entitiesXml = entitiesXml .. string.format('\t\t\t<position x="%f" y="%f" z="%f"/>\n', properties.x, properties.y, properties.z)
			entitiesXml = entitiesXml .. string.format('\t\t\t<rotation w="%f" x="%f" y="%f" z="%f"/>\n', q.w, q.x, q.y, q.z)
			entitiesXml = entitiesXml .. '\t\t\t<scaleXY value="1"/>\n'
			entitiesXml = entitiesXml .. '\t\t\t<scaleZ value="1"/>\n'
			entitiesXml = entitiesXml .. '\t\t\t<parentIndex value="-1"/>\n'
			entitiesXml = entitiesXml .. '\t\t\t<lodDist value="500"/>\n'
			entitiesXml = entitiesXml .. '\t\t\t<childLodDist value="500"/>\n'
			entitiesXml = entitiesXml .. '\t\t\t<lodLevel>LODTYPES_DEPTH_HD</lodLevel>\n'
			entitiesXml = entitiesXml .. '\t\t\t<numChildren value="0"/>\n'
			entitiesXml = entitiesXml .. '\t\t\t<ambientOcclusionMultiplier value="255"/>\n'
			entitiesXml = entitiesXml .. '\t\t\t<artificialAmbientOcclusion value="255"/>\n'
			entitiesXml = entitiesXml .. '\t\t</Item>\n'
		end
	end

	entitiesXml = entitiesXml .. '\t</entities>\n'

	local xml = '<?xml version="1.0"?>\n<CMapData>\n\t<flags value="2"/>\n\t<contentFlags value="65"/>\n'

	if minX and minY and minZ and maxX and maxY and maxZ then
		xml = xml .. string.format('\t<streamingExtentsMin x="%f" y="%f" z="%f"/>\n', minX - 400, minY - 400, minZ - 400)
		xml = xml .. string.format('\t<streamingExtentsMax x="%f" y="%f" z="%f"/>\n', maxX + 400, maxY + 400, maxZ + 400)
		xml = xml .. string.format('\t<entitiesExtentsMin x="%f" y="%f" z="%f"/>\n', minX, minY, minZ)
		xml = xml .. string.format('\t<entitiesExtentsMax x="%f" y="%f" z="%f"/>\n', maxX, maxY, maxZ)

		xml = xml .. entitiesXml
	end

	xml = xml .. '</CMapData>'

	return xml
end

function ConvertDatabaseToPropPlacerJson(database)
	local props = {}

	for entity, properties in pairs(database.spawn) do
		props[properties.yaw .. '-' .. properties.x] = {
			prophash = properties.model,
			x = properties.x,
			y = properties.y,
			z = properties.z,
			heading = properties.yaw
		}
	end

	return json.encode(props)
end

function BackupDbs()
	local dbs = {}

	for _, name in ipairs(GetSavedDatabases()) do
		dbs[name] = LoadDatabaseFromKvs(name)
	end

	return json.encode(dbs)
end

function RestoreDbs(content)
	local dbs = json.decode(content)

	for name, db in pairs(dbs) do
		SaveDatabaseInKvs(name, db)
	end
end

local function loadYmap(xml)
	local curElem, isEntity

	local db = {}
	local i = 0
	local key = "0"

	local parser = SLAXML:parser {
		startElement = function(name, nsURI, nsPrefix)
			curElem = name
		end,
		attribute = function(name, value, nsURI, nsPrefix)
			if name == "type" and value == "CEntityDef" then
				isEntity = true
				db[key] = {
					quaternion = {},
					x = 0.0,
					y = 0.0,
					z = 0.0,
					pitch = 0.0,
					roll = 0.0,
					yaw = 0.0
				}
			elseif curElem == "position" then
				value = (tonumber(value) or 0) + 0.0
				if name == "x" then
					db[key].x = value
				elseif name == "y" then
					db[key].y = value
				elseif name == "z" then
					db[key].z = value
				end
			elseif curElem == "rotation" then
				db[key].quaternion[name] = (tonumber(value) or 0) + 0.0
			elseif isEntity and curElem == "flags" and name == "value" then
				value = tonumber(value) or 0
				db[key].isFrozen = (value & 32) == 32
			end
		end,
		closeElement = function(name, nsURI)
			if isEntity and name == "Item" then
				isEntity = false
				i = i + 1
				key = tostring(i)
			end
			curElem = nil
		end,
		text = function(text, cdata)
			if isEntity then
				if curElem == "archetypeName" then
					db[key].name = text
					db[key].model = GetHashKey(text)
				end
			end
		end
	}

	parser:parse(xml, {stripWhitespace=true})

	LoadDatabase(db, false, false)
end

function ExportDatabase(format)
	UpdateDatabase()

	local db = PrepareDatabaseForSave()

	if format == 'spooner-db-json' then
		return json.encode(db)
	elseif format == 'map-editor-xml' then
		return ConvertDatabaseToMapEditorXml(GetPlayerName(), db)
	elseif format == 'ymap' then
		return ConvertDatabaseToYmap(db)
	elseif format == 'propplacer' then
		return ConvertDatabaseToPropPlacerJson(db)
	elseif format == 'backup' then
		return BackupDbs()
	end
end

function ImportDatabase(format, content)
	if format == 'spooner-db-json' then
		local db = json.decode(content)

		if db then
			LoadDatabase(db, false, false)
		end
	elseif format == 'backup' then
		RestoreDbs(content)
	elseif format == 'ymap' then
		loadYmap(content)
	end
end

RegisterNUICallback('exportDb', function(data, cb)
	cb(ExportDatabase(data.format))
end)

RegisterNUICallback('importDb', function(data, cb)
	ImportDatabase(data.format, data.content)
	cb({})
end)

RegisterNUICallback('closeImportExportDbWindow', function(data, cb)
	SetNuiFocus(false, false)
	cb({})
end)

