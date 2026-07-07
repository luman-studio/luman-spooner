-- ============================================================================
-- spooner :: client/main.lua
-- Main spooner update loop, entity enumeration, on-screen handle drawing, threads
--
-- Part of the split client.lua. All spooner client modules share one Lua state
-- and _G, so globals defined in any module are visible to the others.
-- ============================================================================

function MainSpoonerUpdates()
	if IsUsingKeyboard(0) and IsRawKeyPressed(Config.ToggleControl) then
		TriggerServerEvent('spooner:toggle')
	end

	if Cam then
		DisableAllControlActions(0)
		EnableControlAction(0, `INPUT_MP_TEXT_CHAT_ALL`, true)

		-- Escape should just leave the spooner instead of opening the game's pause
		-- menu. The pause control stays disabled (no EnableControlAction above), so
		-- we detect the press here and toggle the spooner off. When a NUI menu is
		-- focused the key is handled in the UI instead, so this won't fire.
		if IsDisabledControlJustPressed(0, `INPUT_FRONTEND_PAUSE_ALTERNATE`) or IsDisabledControlJustPressed(0, `INPUT_FRONTEND_PAUSE`) then
			TriggerServerEvent('spooner:toggle')
		end

		local x1, y1, z1 = table.unpack(GetCamCoord(Cam))
		local pitch1, roll1, yaw1 = table.unpack(GetCamRot(Cam, 2))

		local x2 = x1
		local y2 = y1
		local z2 = z1
		local pitch2 = pitch1
		local roll2 = roll1
		local yaw2 = yaw1

		local spawnPos, entity, distance = GetInView(x2, y2, z2, pitch2, roll2, yaw2)

		if AttachedEntity then
			entity = AttachedEntity
		elseif FocusTarget and not FreeFocus then
			entity = FocusTarget
		end

		local interiorId = GetInteriorFromPrimaryView() -- Cam
		local interiorName = 'None'
		local interiorRoomName = 'None'
		if interiorId ~= 0 then
			local _,interiorHash = GetInteriorLocationAndNamehash(interiorId)
			interiorName = InteriorsHash[interiorHash] or interiorHash
			
			if Config.isRDR then
				interiorRoomName = 'Unknown'
			else
				local roomHash = GetRoomKeyForGameViewport()
				local roomId = GetInteriorRoomIndexByHash(interiorId, roomHash)
				interiorRoomName = GetInteriorRoomName(interiorId, roomId)
			end

		end
		interiorName = interiorName .. ' (' .. interiorRoomName .. ')'

		SendNUIMessage({
			type = 'updateSpoonerHud',
			entity = entity,
			netId = NetworkGetEntityIsNetworked(entity) and ObjToNet(entity),
			entityType = GetSpoonerEntityType(entity),
			modelName = GetModelName(GetSpoonerEntityModel(entity)),
			attachedEntity = AttachedEntity,
			speed = string.format('%.2f', Speed),
			currentSpawn = CurrentSpawn and CurrentSpawn.modelName,
			rotateMode = RotateMode,
			adjustMode = AdjustMode,
			speedMode = SpeedMode,
			placeOnGround = PlaceOnGround,
			adjustSpeed = AdjustSpeed,
			rotateSpeed = RotateSpeed,
			cursorX = string.format('%.2f', spawnPos.x),
			cursorY = string.format('%.2f', spawnPos.y),
			cursorZ = string.format('%.2f', spawnPos.z),
			camX = string.format('%.2f', x2),
			camY = string.format('%.2f', y2),
			camZ = string.format('%.2f', z2),
			camRotX = string.format('%.2f', pitch2),
			camRotY = string.format('%.2f', roll2),
			camRotZ = string.format('%.2f', yaw2),
			focusTarget = FocusTarget,
			freeFocus = FreeFocus,
			interiorId = interiorName,
		})

		if IsDisabledControlJustPressed(0, Config.IncreaseSpeedControl) then
			if SpeedMode == 0 then
				Speed = Speed + Config.SpeedIncrement
			elseif SpeedMode == 1 then
				AdjustSpeed = AdjustSpeed + Config.AdjustSpeedIncrement
			elseif SpeedMode == 2 then
				RotateSpeed = RotateSpeed + Config.RotateSpeedIncrement
			end
		end

		if IsDisabledControlJustPressed(0, Config.DecreaseSpeedControl) then
			if SpeedMode == 0 then
				Speed = Speed - Config.SpeedIncrement
			elseif SpeedMode == 1 then
				AdjustSpeed = AdjustSpeed - Config.AdjustSpeedIncrement
			elseif SpeedMode == 2 then
				RotateSpeed = RotateSpeed - Config.RotateSpeedIncrement
			end
		end

		if Speed < Config.MinSpeed then
			Speed = Config.MinSpeed
		elseif Speed > Config.MaxSpeed then
			Speed = Config.MaxSpeed
		end

		if AdjustSpeed < Config.MinAdjustSpeed then
			AdjustSpeed = Config.MinAdjustSpeed
		elseif AdjustSpeed > Config.MaxAdjustSpeed then
			AdjustSpeed = Config.MaxAdjustSpeed
		end

		if RotateSpeed < Config.MinRotateSpeed then
			RotateSpeed = Config.MinRotateSpeed
		elseif RotateSpeed > Config.MaxRotateSpeed then
			RotateSpeed = Config.MaxRotateSpeed
		end

		if IsRawKeyDown(Config.UpControl) then
			z2 = z2 + Speed
		end

		if IsRawKeyDown(Config.DownControl) then
			z2 = z2 - Speed
		end

		local axisX = GetDisabledControlNormal(0, Config.LookLrControl)
		local axisY = GetDisabledControlNormal(0, Config.LookUdControl)

		if axisX ~= 0.0 or axisY ~= 0.0 then
			yaw2 = yaw2 + axisX * -1.0 * Config.SpeedUd
			pitch2 = math.max(math.min(89.9, pitch2 + axisY * -1.0 * Config.SpeedLr), -89.9)
		end

		local r1 = -yaw2 * math.pi / 180
		local dx1 = Speed * math.sin(r1)
		local dy1 = Speed * math.cos(r1)

		local r2 = math.floor(yaw2 + 90.0) % 360 * -1.0 * math.pi / 180
		local dx2 = Speed * math.sin(r2)
		local dy2 = Speed * math.cos(r2)

		if IsRawKeyDown(Config.ForwardControl) then
			x2 = x2 + dx1
			y2 = y2 + dy1
		end

		if IsRawKeyDown(Config.BackwardControl) then
			x2 = x2 - dx1
			y2 = y2 - dy1
		end

		if IsRawKeyDown(Config.LeftControl) then
			x2 = x2 + dx2
			y2 = y2 + dy2
		end

		if IsRawKeyDown(Config.RightControl) then
			x2 = x2 - dx2
			y2 = y2 - dy2
		end

		-- Picking point B for the Patrol + Lasso behavior. While active, left click
		-- sets B at the cursor and starts the behavior; right click cancels. Camera
		-- movement stays available so you can aim; the spawn/select/delete handlers
		-- below are disabled while picking (see the `not PendingBehavior` guards).
		if PendingBehavior then
			if IsDisabledControlJustPressed(0, Config.SelectControl) then
				local target = PendingBehavior.entity

				if DoesEntityExist(target) then
					StartPatrolLasso(target, PendingBehavior.a, { x = spawnPos.x, y = spawnPos.y, z = spawnPos.z })
					notify('Patrol + Lasso started')
				end

				PendingBehavior = nil
			elseif IsDisabledControlJustPressed(0, Config.DeleteControl) then
				PendingBehavior = nil
				notify('Patrol setup cancelled')
			end
		end

		if not PendingBehavior and IsRawKeyPressed(Config.SpawnControl) and CurrentSpawn then
			local entity

			if CurrentSpawn.type == 1 then
				entity = SpawnPed{
					name = CurrentSpawn.modelName,
					model = ResolveModelHash(CurrentSpawn.modelName),
					x = spawnPos.x,
					y = spawnPos.y,
					z = spawnPos.z,
					pitch = 0.0,
					roll = 0.0,
					yaw = yaw2,
					collisionDisabled = false,
					isVisible = true,
					outfit = -1,
					isInGroup = false,
					blockNonTemporaryEvents = false
				}

			elseif CurrentSpawn.type == 2 then
				entity = SpawnVehicle(CurrentSpawn.modelName, ResolveModelHash(CurrentSpawn.modelName), spawnPos.x, spawnPos.y, spawnPos.z, 0.0, 0.0, yaw2, false, true)
			elseif CurrentSpawn.type == 3 then
				entity = SpawnObject(CurrentSpawn.modelName, ResolveModelHash(CurrentSpawn.modelName), spawnPos.x, spawnPos.y, spawnPos.z, 0.0, 0.0, yaw2, false, true, nil, nil, nil)
			elseif CurrentSpawn.type == 4 then
				entity = SpawnPropset(CurrentSpawn.modelName, ResolveModelHash(CurrentSpawn.modelName), spawnPos.x, spawnPos.y, spawnPos.z, yaw2)
			elseif CurrentSpawn.type == 5 then
				entity = SpawnPickup(CurrentSpawn.modelName, ResolveModelHash(CurrentSpawn.modelName), spawnPos.x, spawnPos.y, spawnPos.z)
			elseif CurrentSpawn.type == 6 then
				entity = SpawnParticleEffect(CurrentSpawn.modelName, spawnPos.x, spawnPos.y, spawnPos.z, 0.0, 0.0, yaw2, 1.0)
			end

			if entity then
				PlaceOnGroundProperly(entity)
			end
		end

		if not PendingBehavior and IsDisabledControlJustPressed(0, Config.SelectControl) then
			TriggerEvent('spooner:onEntityUnselected', AttachedEntity)
			if AttachedEntity then
				if GetEntityType(AttachedEntity) == 1 then
					-- A frozen ped is shown statically (T-pose) while held, but once placed
					-- its animation/scenario resumes and it visually faces the opposite way.
					-- Flip 180° on placement so it matches how it stood while held. Skip for
					-- peds grabbed without freezing (e.g. a ridden horse), which don't T-pose.
					if HeldWasFrozen then
						local p, r, y = table.unpack(GetEntityRotation(AttachedEntity, 2))
						SetEntityRotation(AttachedEntity, p, r, y + 180.0, 2)
					end

					-- Re-apply the stored pose now that the ped is placed and unfrozen,
					-- so freezing it while held doesn't leave it in a static stance.
					if Database[AttachedEntity] then
						if Database[AttachedEntity].animation then
							PlayAnimation(AttachedEntity, Database[AttachedEntity].animation)
						elseif Database[AttachedEntity].scenario then
							startScenario(AttachedEntity, Database[AttachedEntity].scenario)
						end
					end

					-- Settle the ped on the ground once, now that it's placed (skipped
					-- every frame while held to avoid the flicker).
					PlaceOnGroundProperly(AttachedEntity)

					-- If this ped carries a stored behavior (e.g. a Saved/MP ped with a
					-- patrol route), start it now that it's placed, relative to here.
					RestartBehavior(AttachedEntity)
				end

				AttachedEntity = nil
			elseif entity and CanModifyEntity(entity) then
				if IsEntityAttached(entity) then
					AttachedEntity = GetEntityAttachedTo(entity)
				else
					AttachedEntity = entity
				end
				TriggerEvent('spooner:onEntitySelected', AttachedEntity)
			end
		end

		if not PendingBehavior and IsDisabledControlJustPressed(0, Config.DeleteControl) and entity then
			TriggerEvent('spooner:onEntityUnselected', AttachedEntity)
			if AttachedEntity then
				RemoveEntity(AttachedEntity)
				AttachedEntity = nil
			else
				RemoveEntity(entity)
			end
		end

		if IsRawKeyReleased(Config.SpawnMenuControl) then
			SendNUIMessage({
				type = 'openSpawnMenu'
			})
			SetNuiFocus(true, true)
		end

		if IsRawKeyReleased(Config.DbMenuControl) then
			OpenDatabaseMenu()
		end

		if IsRawKeyReleased(Config.SaveLoadDbMenuControl) then
			OpenSaveDbMenu()
		end

		if IsRawKeyReleased(Config.HelpMenuControl) then
			SendNUIMessage({
				type = 'openHelpMenu'
			})
			SetNuiFocus(true, true)
		end

		if IsRawKeyReleased(Config.ToggleControlsControl) then
			ShowControls = not ShowControls
			if ShowControls then
				SendNUIMessage({
					type = 'showControls'
				})
			else
				SendNUIMessage({
					type = 'hideControls'
				})
			end
		end

		if IsRawKeyPressed(Config.RotateModeControl) then
			RotateMode = (RotateMode + 1) % 3
		end

		if IsRawKeyPressed(Config.AdjustModeControl) then
			if AdjustMode < 4 then
				AdjustMode = (AdjustMode + 1) % 4
			else
				AdjustMode = 0
			end
		end

		if IsRawKeyPressed(Config.FreeAdjustModeControl) then
			AdjustMode = 4
		end

		if IsRawKeyPressed(Config.AdjustOffControl) then
			AdjustMode = 5
		end

		if IsRawKeyPressed(Config.SpeedModeControl) then
			SpeedMode = (SpeedMode + 1) % 3
		end

		if IsRawKeyPressed(Config.PlaceOnGroundControl) then
			PlaceOnGround = not PlaceOnGround
		end

		if IsRawKeyPressed(Config.FocusControl) then
			if not entity or FocusTarget == entity then
				UnfocusEntity()
			else
				TryFocusEntity(entity)
			end
		end

		if FocusTarget and IsRawKeyPressed(Config.ToggleFocusModeControl) then
			if FreeFocus then
				PointCamAtEntity(Cam, FocusTarget)
				FreeFocus = false
			else
				StopCamPointing(Cam)
				FreeFocus = true
			end
		end

		if entity and CanModifyEntity(entity) then
			local posChanged = false
			local rotChanged = false

			if IsRawKeyReleased(Config.PropMenuControl) then
				OpenPropertiesMenuForEntity(entity)
			end

			if IsRawKeyPressed(Config.CloneControl) then
				TriggerEvent('spooner:onEntityUnselected', AttachedEntity)
				AttachedEntity = CloneEntity(entity)
				TriggerEvent('spooner:onEntitySelected', AttachedEntity)
			end

			local ex1, ey1, ez1, epitch1, eroll1, eyaw1

			if Database[entity] and Database[entity].attachment.to > 0 then
				ex1 = Database[entity].attachment.x
				ey1 = Database[entity].attachment.y
				ez1 = Database[entity].attachment.z
				epitch1 = Database[entity].attachment.pitch
				eroll1 = Database[entity].attachment.roll
				eyaw1 = Database[entity].attachment.yaw
			else
				ex1, ey1, ez1 = table.unpack(GetEntityCoords(entity))

				if entity == AttachedEntity and AttachedEntityRotation then
					-- Use the rotation stored when the entity was grabbed as the base,
					-- so a living ped can't drift/reset it between frames
					epitch1 = AttachedEntityRotation.pitch
					eroll1 = AttachedEntityRotation.roll
					eyaw1 = AttachedEntityRotation.yaw
				else
					epitch1, eroll1, eyaw1 = table.unpack(GetEntityRotation(entity, 2))
				end
			end

			local ex2 = ex1
			local ey2 = ey1
			local ez2 = ez1
			local epitch2 = epitch1
			local eroll2 = eroll1
			local eyaw2 = eyaw1

			local edx1, edy1, edx2, edy2

			if Database[entity] and Database[entity].attachment.to > 0 then
				edx1 = 0
				edy1 = AdjustSpeed
				edx2 = AdjustSpeed
				edy2 = 0
			else
				edx1 = AdjustSpeed * math.sin(r1)
				edy1 = AdjustSpeed * math.cos(r1)
				edx2 = AdjustSpeed * math.sin(r2)
				edy2 = AdjustSpeed * math.cos(r2)
			end

			if IsRawKeyDown(Config.RotateLeftControl) then
				if RotateMode == 0 then
					epitch2 = epitch2 + RotateSpeed
				elseif RotateMode == 1 then
					eroll2 = eroll2 + RotateSpeed
				else
					eyaw2 = eyaw2 + RotateSpeed
				end

				rotChanged = true
			end

			if IsRawKeyDown(Config.RotateRightControl) then
				if RotateMode == 0 then
					epitch2 = epitch2 - RotateSpeed
				elseif RotateMode == 1 then
					eroll2 = eroll2 - RotateSpeed
				else
					eyaw2 = eyaw2 - RotateSpeed
				end

				rotChanged = true
			end

			if IsRawKeyDown(Config.AdjustUpControl) then
				ez2 = ez2 + AdjustSpeed
				posChanged = true
			end

			if IsRawKeyDown(Config.AdjustDownControl) then
				ez2 = ez2 - AdjustSpeed
				posChanged = true
			end

			if IsRawKeyDown(Config.AdjustForwardControl) then
				ex2 = ex2 + edx1
				ey2 = ey2 + edy1
				posChanged = true
			end

			if IsRawKeyDown(Config.AdjustBackwardControl) then
				ex2 = ex2 - edx1
				ey2 = ey2 - edy1
				posChanged = true
			end

			if IsRawKeyDown(Config.AdjustLeftControl) then
				ex2 = ex2 + edx2
				ey2 = ey2 + edy2
				posChanged = true
			end

			if IsRawKeyDown(Config.AdjustRightControl) then
				ex2 = ex2 - edx2
				ey2 = ey2 - edy2
				posChanged = true
			end

			if AttachedEntity or posChanged or rotChanged then
				RequestControl(entity)

				if Database[entity] and Database[entity].attachment.to > 0 then
					AttachEntity(entity,
						Database[entity].attachment.to,
						Database[entity].attachment.bone,
						ex2, ey2, ez2,
						epitch2, eroll2, eyaw2,
						Database[entity].attachment.useSoftPinning,
						Database[entity].attachment.collision,
						Database[entity].attachment.vertex,
						Database[entity].attachment.fixedRot)
				else
					if posChanged then
						SetEntityCoordsNoOffset(entity, ex2, ey2, ez2)
					end

					if rotChanged then
						SetEntityRotation(entity, epitch2, eroll2, eyaw2, 2)
					end
				end

				if AttachedEntity then
					local fpitch, froll, fyaw = epitch2, eroll2, eyaw2

					if AdjustMode < 4 then
						x2 = x1
						y2 = y1
						z2 = z1
						pitch2 = pitch1
						yaw2 = yaw1

						if AdjustMode == 0 then
							SetEntityCoordsNoOffset(AttachedEntity, ex2 - axisX, ey2, ez2)
						elseif AdjustMode == 1 then
							SetEntityCoordsNoOffset(AttachedEntity, ex2, ey2 - axisX, ez2)
						elseif AdjustMode == 2 then
							SetEntityCoordsNoOffset(AttachedEntity, ex2, ey2, ez2 - axisY)
						elseif AdjustMode == 3 then
							-- Rotate via mouse along the active axis
							if RotateMode == 0 then
								fpitch = epitch2 - axisX * Config.SpeedLr
							elseif RotateMode == 1 then
								froll = eroll2 - axisX * Config.SpeedLr
							else
								fyaw = eyaw2 - axisX * Config.SpeedLr
							end
						end
					elseif AdjustMode == 4 then
						local fz = spawnPos.z

						-- A ped's coords are its centre, so dropping it straight onto the
						-- cursor point sinks it halfway underground. Offset by the model's
						-- bottom so its feet (not its centre) sit on the surface. Done
						-- manually instead of PlaceEntityOnGroundProperly to avoid the
						-- per-frame re-orientation flicker.
						if GetEntityType(AttachedEntity) == 1 then
							local minDim = GetModelDimensions(GetEntityModel(AttachedEntity))
							fz = spawnPos.z - minDim.z
						end

						SetEntityCoordsNoOffset(AttachedEntity, spawnPos.x, spawnPos.y, fz)
					end

					-- Re-assert the rotation every frame and remember it. This holds the
					-- grabbed entity at the rotation it was taken with (plus any
					-- adjustments) without freezing it, so a ped keeps playing its
					-- animation/scenario pose and never drifts back on its own.
					SetEntityRotation(AttachedEntity, fpitch, froll, fyaw, 2)
					AttachedEntityRotation = { pitch = fpitch, roll = froll, yaw = fyaw }

					-- Don't ground-place a ped every frame: PlaceEntityOnGroundProperly
					-- re-orients the ped each call and makes it flicker (a periodic 180°
					-- snap) while held. The cursor point is already on the surface, so it
					-- follows fine; the ground placement is done once on release instead.
					if (PlaceOnGround or AdjustMode == 4) and GetEntityType(AttachedEntity) ~= 1 then
						PlaceOnGroundProperly(AttachedEntity)
					end
				end
			end
		end

		-- Update preview entity position (follows cursor)
		if PreviewEntity and DoesEntityExist(PreviewEntity) then
			SetEntityCoordsNoOffset(PreviewEntity, spawnPos.x, spawnPos.y, spawnPos.z)
			PlaceOnGroundProperly(PreviewEntity)
		end

		if FocusTarget then
			if DoesEntityExist(FocusTarget) then
				local currentPos = GetEntityCoords(FocusTarget)

				SetCamCoord(Cam, vector3(x2, y2, z2) + (currentPos - FocusTargetPos))

				FocusTargetPos = currentPos
			else
				UnfocusEntity()
			end
		else
			SetCamCoord(Cam, x2, y2, z2)
		end

		SetCamRot(Cam, pitch2, 0.0, yaw2)

		if IsRawKeyPressed(Config.CopyCameraToClipboard) then
			local camRot = GetCamRot(Cam)
			SendNUIMessage({
				type = 'copyCameraToClipboard',
				camX = string.format('%.2f', x2),
				camY = string.format('%.2f', y2),
				camZ = string.format('%.2f', z2),
				camRotX = string.format('%.2f', pitch2),
				camRotY = string.format('%.2f', roll2),
				camRotZ = string.format('%.2f', yaw2),
			})
		end
	end
end

local entityEnumerator = {
	__gc = function(enum)
		if enum.destructor and enum.handle then
			enum.destructor(enum.handle)
		end
		enum.destructor = nil
		enum.handle = nil
	end
}

local function enumerateEntities(firstFunc, nextFunc, endFunc)
	return coroutine.wrap(function()
		local iter, id = firstFunc()

		if not id or id == 0 then
			endFunc(iter)
			return
		end

		local enum = {handle = iter, destructor = endFunc}
		setmetatable(enum, entityEnumerator)

		local next = true
		repeat
			coroutine.yield(id)
			next, id = nextFunc(iter)
		until not next

		enum.destructor, enum.handle = nil, nil
		endFunc(iter)
	end)
end

local function enumeratePeds()
	return enumerateEntities(FindFirstPed, FindNextPed, EndFindPed)
end

local function enumerateVehicles()
	return enumerateEntities(FindFirstVehicle, FindNextVehicle, EndFindVehicle)
end

local function enumerateObjects()
	return enumerateEntities(FindFirstObject, FindNextObject, EndFindObject)
end

local function drawText3d(x, y, z, text)
	local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(x, y, z)

	if onScreen then
		SetTextScale(0.35, 0.35)

		if Config.isRDR then
			SetTextFontForCurrentCommand(1)
			SetTextColor(255, 255, 255, 255)
		else
			SetTextFont(0)
			SetTextColour(255, 255, 255, 255)
		end

		SetTextCentre(1)

		if Config.isRDR then
			DisplayText(CreateVarString(10, "LITERAL_STRING", text), screenX, screenY)
		else
			SetTextEntry("STRING")
			AddTextComponentString(text)
			DrawText(screenX, screenY)
		end
	end
end

local function drawEntityHandle(type, entity, camCoords)
	local coords = GetEntityCoords(entity)

	if #(camCoords - coords) <= Config.EntityHandleDrawDistance then
		drawText3d(coords.x, coords.y, coords.z, type .. " " .. tostring(entity))
	end
end

function drawEntityHandles()
	if Cam then
		if IsRawKeyPressed(Config.EntityHandlesControl) then
			showEntityHandles = not showEntityHandles
		end

		if showEntityHandles then
			local camCoords = GetCamCoord(Cam)

			for ped in enumeratePeds() do
				drawEntityHandle("ped", ped, camCoords)
			end

			for vehicle in enumerateVehicles() do
				drawEntityHandle("vehicle", vehicle, camCoords)
			end

			for object in enumerateObjects() do
				drawEntityHandle("object", object, camCoords)
			end
		end
	end
end

CreateThread(function()
	TriggerEvent('chat:addSuggestion', '/spooner', 'Toggle spooner mode', {})
	TriggerServerEvent('spooner:init')
end)

function UpdateDbEntities()
	local playerPed = PlayerPedId()

	if KeepSelfInDb and not EntityIsInDatabase(playerPed) then
		AddEntityToDatabase(playerPed)
	end

	local enableSpoonerPrompts = false

	for entity, properties in pairs(Database) do
		if not NetworkGetEntityIsNetworked(entity) then
			NetworkRegisterEntityAsNetworked(entity)
		end

		-- Don't re-apply the scenario/animation to a ped that's currently being held
		-- in the camera. While grabbed its tasks are cleared on purpose; re-applying
		-- here (once per second) is what made saved peds snap 180° during the grab.
		if entity ~= AttachedEntity and not (BehaviorPeds and BehaviorPeds[entity]) then
			if properties.scenario then
				local hash = GetHashKey(properties.scenario)

				if not IsPedUsingScenarioHash(entity, hash) then
					startScenario(entity, properties.scenario)
				end
			elseif properties.animation then
				if not IsAnimationPaused(entity) and not IsEntityPlayingAnim(entity, properties.animation.dict, properties.animation.name, 3) then
					PlayAnimation(entity, properties.animation)
				end
			end
		end

		-- Show prompts for certain spooner shortcuts on your own ped
		if Config.isRDR then
			if entity == playerPed then
				-- Don't show the "Clear Tasks" prompt for an animation played with
				-- "Allow Running" (upper-body bone-mask): it's not meant to block
				-- movement, so there should be nothing to manually clear it for.
				local blockingAnimation = properties.animation and properties.animation.filter ~= 'BONEMASK_UPPERONLY'

				if properties.scenario or blockingAnimation then
					if Permissions.properties.ped.clearTasks then
						if not ClearTasksPrompt:isEnabled() then
							ClearTasksPrompt:setEnabledAndVisible(true)
						end

						enableSpoonerPrompts = true
					end
				else
					if ClearTasksPrompt:isEnabled() then
						ClearTasksPrompt:setEnabledAndVisible(false)
					end
				end

				if properties.attachment.bone then
					if Permissions.properties.attachments then
						if not DetachPrompt:isEnabled() then
							DetachPrompt:setEnabledAndVisible(true)
						end
						enableSpoonerPrompts = true
					end
				else
					if DetachPrompt:isEnabled() then
						DetachPrompt:setEnabledAndVisible(false)
					end
				end
			end
		end
	end

	if Config.isRDR then
		if enableSpoonerPrompts then
			if not SpoonerPrompts:isActive() then
				SpoonerPrompts:setActive(true)
			end
		else
			if SpoonerPrompts:isActive() then
				SpoonerPrompts:setActive(false)
			end
		end
	end
end

CreateThread(function()
	while true do
		Wait(1000)
		UpdateDbEntities()
	end
end)

-- ============================================================================
-- Merged from the former client_extended.lua
-- ============================================================================

-------------------------------------------------------
-- Disable collision for entity white it is selected --
-------------------------------------------------------
local hadCollisionDisabled = false
local wasFrozenBeforeSelect = false
AddEventHandler('spooner:onEntitySelected', function(entity)
	if not entity or not DoesEntityExist(entity) then
		return
	end

	-- Disable collision while entity selected
	hadCollisionDisabled = GetEntityCollisionDisabled(entity)
	SetEntityCollision(entity, false)

	-- Remember the rotation the entity had when grabbed so the grab loop can hold it
	-- steady each frame.
	local pitch, roll, yaw = table.unpack(GetEntityRotation(entity, 2))
	AttachedEntityRotation = { pitch = pitch, roll = roll, yaw = yaw }

	-- Freeze peds while held AND clear their tasks. Freezing alone is not enough:
	-- an active scenario/animation keeps driving the ped's heading, which is what
	-- makes the rotation flicker/fight. Clearing the tasks stops that; the stored
	-- animation/scenario is re-applied on placement.
	-- Exception: GrabNoFreeze is set when grabbing a horse that has a rider — freezing
	-- it would dismount the rider, so we grab it without freezing/clearing.
	if GetEntityType(entity) == 1 and not GrabNoFreeze then
		ClearPedTasksImmediately(entity)
		wasFrozenBeforeSelect = IsEntityFrozen(entity)
		FreezeEntityPosition(entity, true)
		HeldWasFrozen = true
	else
		wasFrozenBeforeSelect = false
		HeldWasFrozen = false
	end

	GrabNoFreeze = false
end)

AddEventHandler('spooner:onEntityUnselected', function(entity)
	AttachedEntityRotation = nil

	if not entity or not DoesEntityExist(entity) then
		return
	end

	-- Keep collision disabled if it was before selection
	if not hadCollisionDisabled then
		SetEntityCollision(entity, true)
	end

	-- Restore the ped's freeze state from before it was grabbed
	if GetEntityType(entity) == 1 and not wasFrozenBeforeSelect then
		FreezeEntityPosition(entity, false)
	end
end)
