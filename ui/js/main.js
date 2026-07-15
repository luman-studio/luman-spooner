// ============================================================================
// spooner :: ui/js/main.js
// NUI message dispatcher (window message listener), DOM load/setup bindings, and test()
//
// Split from ui/script.js. Loaded as a classic <script> in ui/index.html in the
// original source order, so all files share one global scope (behaviour preserved).
// ============================================================================

window.addEventListener('message', function(event) {
	switch (event.data.type) {
		case 'showSpoonerHud':
			showSpoonerHud();
			break;
		case 'hideSpoonerHud':
			hideSpoonerHud();
			break;
		case 'updateSpoonerHud':
			updateSpoonerHud(event.data);
			break;
		case 'openSpawnMenu':
			openSpawnMenu();
			break;
		case 'openDatabase':
			openDatabase(event.data);
			break;
		case 'openPropertiesMenu':
			openPropertiesMenu(event.data);
			break;
		case 'openSaveLoadDbMenu':
			openSaveLoadDbMenu(event.data.databaseNames);
			break;
		case 'openHelpMenu':
			openHelpMenu();
			break;
		case 'updatePermissions':
			updatePermissions(event.data);
			break;
		case 'showControls':
			showControls();
			break;
		case 'hideControls':
			hideControls();
			break;
		case 'copyCameraToClipboard':
			copyCameraToClipboard({
				camX: event.data.camX,
				camY: event.data.camY,
				camZ: event.data.camZ,
				camRotX: event.data.camRotX,
				camRotY: event.data.camRotY,
				camRotZ: event.data.camRotZ,
			});
			break;
	}
});

window.addEventListener('load', function() {
	// Initialize unified spawn menu system
	initAllSpawnMenus();

	// Hold-to-look: while a menu is open (NUI focused), holding the right mouse
	// button lets the player move the camera. The game can't see the mouse while
	// NUI is focused, so we detect the press here and tell the client, which drops
	// NUI focus / hides the cursor; the client restores it on release. These only
	// fire while a menu is focused (the browser gets no mouse events otherwise).
	document.addEventListener('contextmenu', function(event) {
		event.preventDefault();
	});

	document.addEventListener('mousedown', function(event) {
		if (event.button === 2) {
			event.preventDefault();
			sendMessage('cameraLookStart', {});
		}
	});

	sendMessage('init', {}).then(resp => resp.json()).then(function(resp) {
		if (resp.favourites) {
			favourites = resp.favourites;
		}

		favouriteTypes.forEach(type => {
			if (!favourites[type] || Array.isArray(favourites[type])) {
				favourites[type] = {};
			}
		});

		peds = JSON.parse(resp.peds);
		horses = peds.filter(function(name) { return name.indexOf('a_c_horse_') === 0; });
		populateSpawnMenu('ped', '', true);
		populateSpawnMenu('horse', '', true);
		populatePlayerModelList();

		vehicles = JSON.parse(resp.vehicles);
		populateSpawnMenu('vehicle', '', true);

		objects = JSON.parse(resp.objects);
		populateSpawnMenu('object', '', true);

		scenarios = JSON.parse(resp.scenarios);
		populateScenarioList();

		weapons = JSON.parse(resp.weapons);
		populateWeaponList();

		animations = JSON.parse(resp.animations);
		populateAnimationList();

		propsets = JSON.parse(resp.propsets);
		populateSpawnMenu('propset', '', true);

		pickups = JSON.parse(resp.pickups);
		populateSpawnMenu('pickup', '', true);

		particles = JSON.parse(resp.particles);
		populateSpawnMenu('particle', '', true);

		bones = JSON.parse(resp.bones);
		populateBoneNameList();

		walkStyleBases = JSON.parse(resp.walkStyleBases);
		walkStyles = JSON.parse(resp.walkStyles);
		populateWalkStyleList();

		document.querySelectorAll('.adjust-speed').forEach(e => e.value = resp.adjustSpeed);
		document.querySelectorAll('.adjust-input').forEach(e => e.step = resp.adjustSpeed);

		document.querySelectorAll('.rotate-speed').forEach(e => e.value = resp.rotateSpeed);
		document.querySelectorAll('.rotate-input').forEach(e => e.step = resp.rotateSpeed);
	});

	// Player model search (not unified - different behavior)
	document.querySelector('#player-model-search-filter').addEventListener('input', function(event) {
		populatePlayerModelList(this.value);
	});

	// Legacy close button handlers removed - now handled by initAllSpawnMenus()
	// Search filter handlers removed - now handled by initAllSpawnMenus()

	// Scenario search (not a spawn menu with preview)
	document.querySelector('#scenario-search-filter').addEventListener('input', function(event) {
		populateScenarioList(this.value);
	});

	// Bone search
	document.querySelector('#bone-search-filter').addEventListener('input', function(event) {
		populateBoneNameList(this.value);
	});

	// Player model spawn (different behavior - not a spawn menu)
	document.querySelector('#player-model-spawn-by-name').addEventListener('click', function(event) {
		setPlayerModel(document.querySelector('#player-model-search-filter').value);
	});

	document.getElementById('player-model-menu-close-btn').addEventListener('click', function(event) {
		document.querySelector('#player-model-menu').style.display = 'none';
		document.querySelector('#ped-options-menu').style.display = 'flex';
	});

	// Note: ped, vehicle, object, propset, pickup menu handlers are now in initAllSpawnMenus()

	document.querySelector('#object-database-delete-all-btn').addEventListener('click', function(event) {
		removeAllFromDatabase();
	});

	document.querySelector('#object-database-close-btn').addEventListener('click', function(event) {
		closeDatabase();
	});

	document.querySelector('#properties-add-to-db').addEventListener('click', function(event) {
		sendMessage('addEntityToDatabase', {
			handle: currentEntity()
		}).then(resp => resp.json()).then(function(resp) {
			document.querySelector('#properties-add-to-db').style.display = 'none';
			document.querySelector('#properties-remove-from-db').style.display = 'block';
		});
	});

	document.querySelector('#properties-remove-from-db').addEventListener('click', function(event) {
		sendMessage('removeEntityFromDatabase', {
			handle: currentEntity()
		}).then(resp => resp.json()).then(function(resp) {
			document.querySelector('#properties-add-to-db').style.display = 'block';
			document.querySelector('#properties-remove-from-db').style.display = 'none';
		});
	});

	document.querySelector('#properties-save-ped').addEventListener('click', function(event) {
		var nameInput = document.querySelector('#save-ped-name');
		var name = nameInput.value.trim();

		if (!name) {
			nameInput.focus();
			return;
		}

		var btn = document.querySelector('#properties-save-ped');

		sendMessage('saveCurrentPed', {
			handle: currentEntity(),
			name: name
		}).then(resp => resp.json()).then(function(resp) {
			nameInput.value = '';

			var original = btn.innerHTML;
			btn.innerHTML = '<i class="fas fa-check"></i> Saved!';
			setTimeout(function() { btn.innerHTML = original; }, 1200);
		});
	});

	document.querySelector('#properties-save-mp-ped').addEventListener('click', function(event) {
		var nameInput = document.querySelector('#save-ped-name');
		var name = nameInput.value.trim();

		if (!name) {
			nameInput.focus();
			return;
		}

		var btn = document.querySelector('#properties-save-mp-ped');

		sendMessage('saveCurrentMpPed', {
			handle: currentEntity(),
			name: name
		}).then(resp => resp.json()).then(function(resp) {
			nameInput.value = '';

			var original = btn.innerHTML;
			btn.innerHTML = '<i class="fas fa-check"></i> Saved!';
			setTimeout(function() { btn.innerHTML = original; }, 1200);
		});
	});

	document.querySelector('#properties-copy-animation-prop').addEventListener('click', function(event) {
		sendMessage('copyAnimationProp', {
			handle: currentEntity()
		}).then(resp => resp.json()).then(function(resp) {
			var saveBtn = document.querySelector('#properties-save-animprop');

			if (resp && resp.ok) {
				saveBtn.disabled = false;
				var parts = [];
				if (resp.hasAnimation) parts.push('animation');
				if (resp.propCount) parts.push(resp.propCount + ' prop' + (resp.propCount === 1 ? '' : 's'));
				notify('Copied ' + parts.join(' + '));
			} else {
				saveBtn.disabled = true;
				notify('Nothing to copy: this ped has no animation and no attached props');
			}
		});
	});

	document.querySelector('#properties-save-animprop').addEventListener('click', function(event) {
		var nameInput = document.querySelector('#save-animprop-name');
		var name = nameInput.value.trim();

		if (!name) {
			nameInput.focus();
			return;
		}

		var btn = document.querySelector('#properties-save-animprop');

		sendMessage('saveAnimationProp', {
			name: name
		}).then(resp => resp.json()).then(function(resp) {
			nameInput.value = '';

			var original = btn.innerHTML;
			btn.innerHTML = '<i class="fas fa-check"></i> Saved!';
			setTimeout(function() { btn.innerHTML = original; }, 1200);
		});
	});

	document.querySelector('#properties-animprops-list').addEventListener('click', function(event) {
		openAnimPropsMenu();
	});

	document.querySelector('#animprops-menu-back').addEventListener('click', function(event) {
		closeAnimPropsMenu();
	});

	document.querySelector('#movement-start').addEventListener('click', function(event) {
		var handle = currentEntity();
		var run = document.querySelector('#movement-run').checked;
		var lasso = document.querySelector('#movement-lasso').checked;
		var loop = document.querySelector('#movement-loop').checked;
		closePropertiesMenu(true);
		sendMessage('setupMovement', {
			handle: handle,
			run: run,
			lasso: lasso,
			loop: loop
		});
	});

	document.querySelector('#movement-stop').addEventListener('click', function(event) {
		sendMessage('clearMovement', {
			handle: currentEntity()
		});
	});

	document.querySelector('#properties-freeze').addEventListener('click', function(event) {
		sendMessage('freezeEntity', {
			handle: currentEntity()
		});
	});

	document.querySelector('#properties-unfreeze').addEventListener('click', function(event) {
		sendMessage('unfreezeEntity', {
			handle: currentEntity()
		});
	});

	document.querySelectorAll('.set-coords').forEach(function(e) {
		e.addEventListener('input', function(event) {
			sendMessage('setEntityCoords', {
				handle: currentEntity(),
				x: parseFloat(document.querySelector('#properties-x').value),
				y: parseFloat(document.querySelector('#properties-y').value),
				z: parseFloat(document.querySelector('#properties-z').value)
			});
		});
	});

	document.querySelector('#properties-place-here').addEventListener('click', function(event) {
		sendMessage('placeEntityHere', {
			handle: currentEntity()
		}).then(resp => resp.json()).then(function(resp) {
			document.querySelector('#properties-x').value = resp.x;
			document.querySelector('#properties-y').value = resp.y;
			document.querySelector('#properties-z').value = resp.z;
			document.querySelector('#properties-pitch').value = resp.pitch;
			document.querySelector('#properties-roll').value = resp.roll;
			document.querySelector('#properties-yaw').value = resp.pitch;
		});
	});

	document.querySelector('#properties-goto').addEventListener('click', function(event) {
		closePropertiesMenu(true);
		goToEntity(currentEntity())
	});

	document.querySelectorAll('.set-rotation').forEach(function(e) {
		e.addEventListener('input', function(event) {
			sendMessage('setEntityRotation', {
				handle: currentEntity(),
				pitch: parseFloat(document.querySelector('#properties-pitch').value),
				roll: parseFloat(document.querySelector('#properties-roll').value),
				yaw: parseFloat(document.querySelector('#properties-yaw').value)
			});
		});
	});

	document.querySelector('#properties-reset-rotation').addEventListener('click', function(event) {
		sendMessage('resetRotation', {
			handle: currentEntity()
		});
		document.querySelector('#properties-pitch').value = 0.0;
		document.querySelector('#properties-roll').value = 0.0;
		document.querySelector('#properties-yaw').value = 0.0;
	});

	document.querySelector('#properties-invincible-on').addEventListener('click', function(event) {
		sendMessage('invincibleOn', {
			handle: currentEntity()
		});
	});

	document.querySelector('#properties-invincible-off').addEventListener('click', function(event) {
		sendMessage('invincibleOff', {
			handle: currentEntity()
		});
	});

	document.querySelector('#properties-clone').addEventListener('click', function(event) {
		sendMessage('cloneEntity', {
			handle: currentEntity()
		});
	});

	document.querySelector('#properties-copy-animation').addEventListener('click', function(event) {
		sendMessage('copyAnimation', {
			handle: currentEntity()
		}).then(resp => resp.json()).then(function(resp) {
			if (resp && resp.ok) {
				copiedAnimation = {
					dict: resp.dict,
					name: resp.name,
					blendInSpeed: resp.blendInSpeed,
					blendOutSpeed: resp.blendOutSpeed,
					duration: resp.duration,
					flag: resp.flag,
					playbackRate: resp.playbackRate,
					filter: resp.filter
				};
			} else {
				copiedAnimation = null;
			}
		});
	});

	document.querySelector('#properties-paste-animation').addEventListener('click', function(event) {
		if (!copiedAnimation) {
			return;
		}

		// Re-apply using the exact same path as the animation tab
		sendMessage('playAnimation', {
			handle: currentEntity(),
			dict: copiedAnimation.dict,
			name: copiedAnimation.name,
			blendInSpeed: copiedAnimation.blendInSpeed,
			blendOutSpeed: copiedAnimation.blendOutSpeed,
			duration: copiedAnimation.duration,
			flag: copiedAnimation.flag,
			filter: copiedAnimation.filter,
			playbackRate: copiedAnimation.playbackRate
		});
	});

	document.querySelector('#properties-copy-scenario').addEventListener('click', function(event) {
		sendMessage('copyScenario', {
			handle: currentEntity()
		}).then(resp => resp.json()).then(function(resp) {
			copiedScenario = (resp && resp.ok) ? resp.scenario : null;
		});
	});

	document.querySelector('#properties-paste-scenario').addEventListener('click', function(event) {
		if (!copiedScenario) {
			return;
		}

		// Re-apply using the exact same path as the scenario tab
		sendMessage('performScenario', {
			handle: currentEntity(),
			scenario: copiedScenario
		});
	});

	document.querySelector('#properties-clear-tasks-props').addEventListener('click', function(event) {
		sendMessage('clearTasksAndProps', {
			handle: currentEntity()
		});
	});

	document.querySelector('#properties-delete').addEventListener('click', function(event) {
		sendMessage('deleteEntity', {
			handle: currentEntity()
		});

		closePropertiesMenu(true);
	});

	document.querySelector('#properties-menu-close-btn').addEventListener('click', function(event) {
		closePropertiesMenu(true);
	});

	document.querySelector('#save-db-btn').addEventListener('click', function(event) {
		sendMessage('saveDb', {
			name: document.querySelector('#save-db-name').value
		}).then(resp => resp.json()).then(resp => updateDbList(resp));
	});

	document.querySelector('#import-export-db-btn').addEventListener('click', function(event) {
		document.querySelector('#save-load-db-menu').style.display = 'none';
		document.querySelector('#import-export-db').style.display = 'flex';
	});

	document.querySelector('#import-db').addEventListener('click', function(event) {
		var url = document.querySelector('#import-url').value;

		if (url) {
			fetch(url).then(resp => resp.text()).then(function(text) {
				document.querySelector('#import-export-content').value = text;

				sendMessage('importDb', {
					format: document.querySelector('#import-export-format').value,
					content: text
				});
			});
		} else {
			sendMessage('importDb', {
				format: document.querySelector('#import-export-format').value,
				content: document.querySelector('#import-export-content').value
			});
		}
	});

	document.querySelector('#export-db').addEventListener('click', function(event) {
		sendMessage('exportDb', {
			format: document.querySelector('#import-export-format').value
		}).then(resp => resp.json()).then(function(resp) {
			document.querySelector('#import-export-content').value = resp;
		});
	});

	document.querySelector('#import-export-db-close').addEventListener('click', function(event) {
		document.querySelector('#import-export-db').style.display = 'none';
		sendMessage('closeImportExportDbWindow', {});
	});

	document.querySelector('#save-load-db-menu-close-btn').addEventListener('click', function(event) {
		closeSaveLoadDbMenu();
	});

	document.querySelectorAll('.adjust-speed').forEach(e => e.addEventListener('input', function(event) {
		document.querySelectorAll('.adjust-speed').forEach(e => e.value = this.value);
		document.querySelectorAll('.adjust-input').forEach(e => e.step = this.value);

		sendMessage('setAdjustSpeed', {
			speed: this.value
		});
	}));

	document.querySelectorAll('.rotate-speed').forEach(e => e.addEventListener('input', function(event) {
		document.querySelectorAll('.rotate-speed').forEach(e => e.value = this.value);
		document.querySelectorAll('.rotate-input').forEach(e => e.step = this.value);

		sendMessage('setRotateSpeed', {
			speed: this.value
		});
	}));

	document.querySelector('#help-menu-close-btn').addEventListener('click', function(event) {
		closeHelpMenu();
	});

	document.querySelector('#spawn-menu-peds').addEventListener('click', function(event) {
		openPedMenu();
	});

	document.querySelector('#spawn-menu-horses').addEventListener('click', function(event) {
		openHorseMenu();
	});

	document.querySelector('#spawn-menu-vehicles').addEventListener('click', function(event) {
		openVehicleMenu();
	});

	document.querySelector('#spawn-menu-objects').addEventListener('click', function(event) {
		openObjectMenu();
	});

	document.querySelector('#spawn-menu-propsets').addEventListener('click', function(event) {
		openPropsetMenu();
	});

	document.querySelector('#spawn-menu-pickups').addEventListener('click', function(event) {
		openPickupMenu();
	});

	document.querySelector('#spawn-menu-saved-peds').addEventListener('click', function(event) {
		openSavedPedsMenu();
	});

	document.querySelector('#saved-peds-menu-back').addEventListener('click', function(event) {
		closeSavedPedsMenu(false);
	});

	document.querySelector('#spawn-menu-mp-peds').addEventListener('click', function(event) {
		openMpPedsMenu();
	});

	document.querySelector('#spawn-menu-particles').addEventListener('click', function(event) {
		openParticleMenu();
	});

	document.querySelector('#particle-menu-view-placed').addEventListener('click', function(event) {
		openPlacedParticlesMenu();
	});

	document.querySelector('#placed-particles-menu-back').addEventListener('click', function(event) {
		closePlacedParticlesMenu();
	});

	document.querySelector('#mp-peds-menu-back').addEventListener('click', function(event) {
		closeMpPedsMenu(false);
	});

	document.querySelector('#mp-peds-create-custom').addEventListener('click', function(event) {
		openCustomMpPedMenu('male');
	});

	document.querySelector('#mp-custom-gender-male').addEventListener('click', function(event) {
		sendMessage('customPedSetGender', { gender: 'male' }).then(resp => resp.json()).then(resp => renderCustomMpPed(resp));
	});

	document.querySelector('#mp-custom-gender-female').addEventListener('click', function(event) {
		sendMessage('customPedSetGender', { gender: 'female' }).then(resp => resp.json()).then(resp => renderCustomMpPed(resp));
	});

	document.querySelector('#mp-custom-randomize').addEventListener('click', function(event) {
		sendMessage('customPedRandomizeAll', {}).then(resp => resp.json()).then(resp => renderCustomMpPed(resp));
	});

	document.querySelector('#mp-custom-save').addEventListener('click', function(event) {
		var nameInput = document.querySelector('#mp-custom-save-name');
		var name = nameInput.value.trim();

		if (!name || customPedEditingHandle === null) {
			nameInput.focus();
			return;
		}

		var btn = document.querySelector('#mp-custom-save');

		sendMessage('saveCurrentMpPed', {
			handle: customPedEditingHandle,
			name: name
		}).then(resp => resp.json()).then(function(resp) {
			nameInput.value = '';

			var original = btn.innerHTML;
			btn.innerHTML = '<i class="fas fa-check"></i> Saved!';
			setTimeout(function() { btn.innerHTML = original; }, 1200);
		});
	});

	document.querySelector('#mp-custom-menu-back').addEventListener('click', function(event) {
		closeCustomMpPedMenu();
	});

	document.querySelector('#spawn-menu-close').addEventListener('click', function(event) {
		closeSpawnMenu();
	});

	document.querySelector('#properties-get-in').addEventListener('click', function(event) {
		closePropertiesMenu(true);
		getIntoVehicle(currentEntity())
	});

	document.querySelector('#properties-repair-vehicle').addEventListener('click', function(event) {
		sendMessage('repairVehicle', {
			handle: currentEntity()
		});
	});

	document.querySelector('#properties-request-control').addEventListener('click', function(event) {
		sendMessage('requestControl', {
			handle: currentEntity()
		});
	});

	document.querySelector('#properties-attach').addEventListener('click', function(event) {
		closePropertiesMenu(false);
		sendMessage('getDatabase', {handle: currentEntity()}).then(resp => resp.json()).then(resp => openAttachToMenu(currentEntity(), resp));
	});

	document.querySelector('#attachment-options-menu-close').addEventListener('click', function(event) {
		document.querySelector('#attachment-options-menu').style.display = 'none';
		sendMessage('openPropertiesMenuForEntity', {
			entity: currentEntity()
		});

	});

	document.querySelector('#attachment-options-detach').addEventListener('click', function(event) {
		document.querySelector('#attachment-options-menu').style.display = 'none';
		sendMessage('detach', {
			handle: currentEntity()
		});
		sendMessage('getDatabase', {handle: currentEntity()}).then(resp => resp.json()).then(resp => openAttachToMenu(currentEntity(), resp));
	});

	document.querySelectorAll('.set-attach').forEach(e => e.addEventListener('input', function(event) {
		var boneName = document.getElementById('attachment-bone-name').value;
		var boneIndex = parseInt(document.getElementById('attachment-bone-index').value);

		sendMessage('attachTo', {
			from: currentEntity(),
			to: null,
			bone: boneName == '' ? boneIndex : boneName,
			x: parseFloat(document.getElementById('attachment-x').value),
			y: parseFloat(document.getElementById('attachment-y').value),
			z: parseFloat(document.getElementById('attachment-z').value),
			pitch: parseFloat(document.getElementById('attachment-pitch').value),
			roll: parseFloat(document.getElementById('attachment-roll').value),
			yaw: parseFloat(document.getElementById('attachment-yaw').value),
			useSoftPinning: document.getElementById('attachment-use-soft-pinning').checked,
			collision: document.getElementById('attachment-collision').checked,
			vertex: parseInt(document.getElementById('attachment-vertex').value),
			fixedRot: document.getElementById('attachment-fixed-rot').checked,
			keepPos: false
		});
	}));

	document.querySelector('#properties-health').addEventListener('input', function(event) {
		sendMessage('setEntityHealth', {
			handle: currentEntity(),
			health: parseInt(this.value)
		});
	});

	document.querySelector('#properties-visible').addEventListener('click', function(event) {
		sendMessage('setEntityVisible', {
			handle: currentEntity()
		});
	});

	document.querySelector('#properties-invisible').addEventListener('click', function(event) {
		sendMessage('setEntityInvisible', {
			handle: currentEntity()
		});
	});

	document.querySelector('#properties-gravity-on').addEventListener('click', function(event) {
		sendMessage('gravityOn', {
			handle: currentEntity()
		});
	});

	// TODO: Add permission
	document.querySelector('#properties-physics-push').addEventListener('click', function(event) {
		sendMessage('physicsPush', {
			handle: currentEntity()
		});
	});

	document.querySelector('#properties-gravity-off').addEventListener('click', function(event) {
		sendMessage('gravityOff', {
			handle: currentEntity()
		});
	});

	document.querySelector('#properties-scenario').addEventListener('click', function(event) {
		document.querySelector('#ped-options-menu').style.display = 'none';
		document.querySelector('#scenario-menu').style.display = 'flex';
	});

	document.querySelector('#scenario-menu-close').addEventListener('click', function(event) {
		document.querySelector('#scenario-menu').style.display = 'none';
		document.querySelector('#ped-options-menu').style.display = 'flex';
	});

	document.querySelector('#scenario-search-filter').addEventListener('input', function(event) {
		populateScenarioList(this.value);
	});

	document.querySelector('#properties-emotions').addEventListener('click', function(event) {
		document.querySelector('#ped-options-menu').style.display = 'none';
		document.querySelector('#emotion-menu').style.display = 'flex';

		if (pedMoods.length === 0) {
			sendMessage('getPedMoods', {}).then(resp => resp.json()).then(function(raw) {
				pedMoods = typeof raw === 'string' ? JSON.parse(raw) : raw;
				populateEmotionList();
			});
		} else {
			populateEmotionList();
		}
	});

	document.querySelector('#emotion-menu-close').addEventListener('click', function(event) {
		document.querySelector('#emotion-menu').style.display = 'none';
		document.querySelector('#ped-options-menu').style.display = 'flex';
	});

	document.querySelector('#emotion-stop').addEventListener('click', function(event) {
		sendMessage('clearPedMood', {
			handle: currentEntity()
		});
	});

	// ===================== Emotes =====================
	document.querySelector('#properties-emotes').addEventListener('click', function(event) {
		document.querySelector('#ped-options-menu').style.display = 'none';
		document.querySelector('#emotes-menu').style.display = 'flex';

		if (emotesData.length === 0) {
			sendMessage('getEmotes', {}).then(function(resp) { return resp.json(); }).then(function(raw) {
				emotesData = typeof raw === 'string' ? JSON.parse(raw) : raw;
				populateEmotesCategories();
			});
		} else {
			populateEmotesCategories();
		}
	});

	document.querySelector('#emotes-menu-close').addEventListener('click', function(event) {
		document.querySelector('#emotes-menu').style.display = 'none';
		document.querySelector('#ped-options-menu').style.display = 'flex';
	});

	document.querySelector('#emotes-list-menu-close').addEventListener('click', function(event) {
		document.querySelector('#emotes-list-menu').style.display = 'none';
		document.querySelector('#emotes-menu').style.display = 'flex';
	});

	document.querySelector('#emotes-search-filter').addEventListener('input', function(event) {
		populateEmotesList(this.value);
	});

	document.querySelector('#emotes-stop').addEventListener('click', function(event) {
		sendMessage('stopEmote', { handle: currentEntity() });
	});

	document.querySelector('#emotes-list-stop').addEventListener('click', function(event) {
		sendMessage('stopEmote', { handle: currentEntity() });
	});

	document.querySelector('#properties-clear-ped-tasks').addEventListener('click', function(event) {
		sendMessage('clearPedTasks', {
			handle: currentEntity()
		});
	});

	document.querySelector('#properties-clear-ped-tasks-immediately').addEventListener('click', function(event) {
		sendMessage('clearPedTasksImmediately', {
			handle: currentEntity()
		});
	});

	document.querySelector('#properties-outfit').addEventListener('input', function(event) {
		sendMessage('setOutfit', {
			handle: currentEntity(),
			outfit: parseInt(this.value)
		});
	});

	document.querySelector('#properties-add-to-group').addEventListener('click', function(event) {
		sendMessage('addToGroup', {
			handle: currentEntity()
		});
	});

	document.querySelector('#properties-remove-from-group').addEventListener('click', function(event) {
		sendMessage('removeFromGroup', {
			handle: currentEntity()
		});
	});

	document.querySelector('#properties-collision-on').addEventListener('click', function(event) {
		sendMessage('collisionOn', {
			handle: currentEntity()
		});
	});

	document.querySelector('#properties-collision-off').addEventListener('click', function(event) {
		sendMessage('collisionOff', {
			handle: currentEntity()
		});
	});

	document.querySelector('#properties-ped-options').addEventListener('click', function(event) {
		document.querySelector('#properties-menu').style.display = 'none';
		document.querySelector('#ped-options-menu').style.display = 'flex';
	});

	document.querySelector('#ped-options-menu-close').addEventListener('click', function(event) {
		document.querySelector('#ped-options-menu').style.display = 'none';
		document.querySelector('#properties-menu').style.display = 'flex';
	});

	document.querySelector('#properties-vehicle-options').addEventListener('click', function(event) {
		document.querySelector('#properties-menu').style.display = 'none';
		document.querySelector('#vehicle-options-menu').style.display = 'flex';
	});

	document.querySelector('#vehicle-options-menu-close').addEventListener('click', function(event) {
		document.querySelector('#vehicle-options-menu').style.display = 'none';
		document.querySelector('#properties-menu').style.display = 'flex';
	});

	document.querySelector('#properties-give-weapon').addEventListener('click', function(event) {
		document.querySelector('#ped-options-menu').style.display = 'none';
		document.querySelector('#weapon-menu').style.display = 'flex';
	});

	document.querySelector('#weapon-search-filter').addEventListener('input', function(event) {
		populateWeaponList(this.value);
	});

	document.querySelector('#properties-holster-weapon').addEventListener('click', function(event) {
		sendMessage('holsterWeapon', {
			handle: currentEntity()
		});
	});

	document.querySelector('#properties-remove-all-weapons').addEventListener('click', function(event) {
		sendMessage('removeAllWeapons', {
			handle: currentEntity()
		});
	});

	document.querySelector('#weapon-menu-close').addEventListener('click', function(event) {
		document.querySelector('#weapon-menu').style.display = 'none';
		document.querySelector('#ped-options-menu').style.display = 'flex';
	});

	document.querySelector('#properties-resurrect-ped').addEventListener('click', function(event) {
		sendMessage('resurrectPed', {
			handle: currentEntity()
		});
	});

	document.querySelector('#properties-engine-on').addEventListener('click', function(event) {
		sendMessage('engineOn', {
			handle: currentEntity()
		});
	});

	document.querySelector('#properties-engine-off').addEventListener('click', function(event) {
		sendMessage('engineOff', {
			handle: currentEntity()
		});
	});

	document.querySelector('#properties-lights-options').addEventListener('click', function(event) {
		document.querySelector('#properties-menu').style.display = 'none';
		document.querySelector('#lights-options-menu').style.display = 'flex';
	});

	document.querySelector('#lights-options-menu-close').addEventListener('click', function(event) {
		document.querySelector('#lights-options-menu').style.display = 'none';
		document.querySelector('#properties-menu').style.display = 'flex';
	});

	document.querySelector('#properties-lights-intensity').addEventListener('input', function(event) {
		sendMessage('setLightsIntensity', {
			handle: currentEntity(),
			intensity: parseFloat(this.value)
		});
	});

	document.querySelectorAll('.lights-colour').forEach(e => e.addEventListener('input', function(event) {
		sendMessage('setLightsColour', {
			handle: currentEntity(),
			red: parseFloat(document.querySelector('#properties-lights-red').value),
			green: parseFloat(document.querySelector('#properties-lights-green').value),
			blue: parseFloat(document.querySelector('#properties-lights-blue').value)
		});
	}));

	document.querySelector('#properties-lights-type').addEventListener('click', function(event) {
		sendMessage('setLightsType', {
			handle: currentEntity(),
			type: parseInt(this.value)
		});
	});

	document.querySelector('#properties-vehicle-lights-on').addEventListener('click', function(event) {
		sendMessage('setVehicleLightsOn', {
			handle: currentEntity()
		});
	});

	document.querySelector('#properties-vehicle-lights-off').addEventListener('click', function(event) {
		sendMessage('setVehicleLightsOff', {
			handle: currentEntity()
		});
	});

	document.querySelector('#properties-ai-on').addEventListener('click', function(event) {
		sendMessage('aiOn', {
			handle: currentEntity()
		});
	});

	document.querySelector('#properties-ai-off').addEventListener('click', function(event) {
		sendMessage('aiOff', {
			handle: currentEntity()
		});
	});

	document.querySelector('#properties-animation').addEventListener('click', function(event) {
		document.querySelector('#properties-menu').style.display = 'none';
		document.querySelector('#animation-menu').style.display = 'flex';
	});

	document.querySelector('#animation-menu-close').addEventListener('click', function(event) {
		document.querySelector('#animation-menu').style.display = 'none';
		document.querySelector('#properties-menu').style.display = 'flex';
	});

	document.querySelector('#animation-open-list').addEventListener('click', function(event) {
		document.querySelector('#animation-menu').style.display = 'none';
		document.querySelector('#animation-list-menu').style.display = 'flex';
	});

	document.querySelector('#animation-list-menu-close').addEventListener('click', function(event) {
		document.querySelector('#animation-list-menu').style.display = 'none';
		document.querySelector('#animation-menu').style.display = 'flex';
		stopAnimTimeline();
	});

	document.querySelector('#animation-search-filter').addEventListener('input', function(event) {
		populateAnimationList(this.value);
	});

	document.querySelector('#animation-search-max-results').addEventListener('input', function(event) {
		populateAnimationList(document.querySelector('#animation-search-filter').value)
	});

	document.querySelector('#pickup-search-filter').addEventListener('input', function(event) {
		populatePickupList(this.value);
	});

	document.getElementById('properties-player-model').addEventListener('click', function(event) {
		document.querySelector('#ped-options-menu').style.display = 'none';
		document.querySelector('#player-model-menu').style.display = 'flex';
	});

	document.getElementById('properties-customize-ped').addEventListener('click', function(event) {
		openCustomizePedMenu(currentEntity());
	});

	document.getElementById('properties-knock-off-props').addEventListener('click', function(event) {
		sendMessage('knockOffProps', {
			handle: currentEntity()
		});
	});

	document.getElementById('walk-style-search-filter').addEventListener('input', function(event) {
		populateWalkStyleList(this.value);
	});

	document.getElementById('properties-walk-style').addEventListener('click', function(event) {
		document.getElementById('ped-options-menu').style.display = 'none';
		document.getElementById('walk-style-menu').style.display = 'flex';
	});

	document.getElementById('walk-style-menu-close').addEventListener('click', function(event) {
		document.getElementById('walk-style-menu').style.display = 'none';
		document.getElementById('ped-options-menu').style.display = 'flex';
	});

	document.getElementById('store-deleted').addEventListener('input', function(event) {
		sendMessage('setStoreDeleted', {
			toggle: this.checked
		});
	});

	document.getElementById('properties-clone-to-target').addEventListener('click', function(event) {
		var handle = currentEntity();
		openEntitySelect('ped-options-menu', function(entity) {
			sendMessage('clonePedToTarget', {
				handle: handle,
				target: entity
			});
		}, handle);
	});

	document.getElementById('properties-look-at-entity').addEventListener('click', function(event) {
		var handle = currentEntity();
		openEntitySelect('ped-options-menu', function(entity) {
			sendMessage('lookAtEntity', {
				handle: handle,
				target: entity
			});
		}, handle);
	});

	document.getElementById('properties-clear-look-at').addEventListener('click', function(event) {
		sendMessage('clearLookAt', {
			handle: currentEntity()
		});
	});

	document.getElementById('properties-set-on-mount').addEventListener('click', function(event) {
		var handle = currentEntity();
		openEntitySelect('ped-options-menu', function(entity) {
			sendMessage('setOnMount', {
				handle: handle,
				entity: entity
			});
		}, handle);
	});

	document.getElementById('properties-enter-vehicle').addEventListener('click', function(event) {
		var handle = currentEntity();
		openEntitySelect('ped-options-menu', function(entity) {
			sendMessage('enterVehicle', {
				handle: handle,
				entity: entity
			});
		}, handle);
	});

	document.getElementById('properties-register-as-networked').addEventListener('click', function(event) {
		sendMessage('registerAsNetworked', {
			handle: currentEntity()
		});
	});

	document.querySelectorAll('.favourites').forEach(e => e.addEventListener('click', function(event) {
		var active = this.hasAttribute('data-active');

		if (active) {
			this.removeAttribute('data-active');
			this.innerHTML = '<i class="far fa-star"></i>';
			this.style.color = null;
		} else {
			this.setAttribute('data-active', '');
			this.innerHTML = '<i class="fas fa-star"></i>';
			this.style.color = 'gold';
		}

		switch (this.id) {
			case 'favourite-peds':
				populatePedList(document.getElementById('ped-search-filter').value);
				break;
			case 'favourite-vehicles':
				populateVehicleList(document.getElementById('vehicle-search-filter').value);
				break;
			case 'favourite-objects':
				populateObjectList(document.getElementById('object-search-filter').value, true);
				break;
			case 'favourite-player-models':
				populatePlayerModelList(document.getElementById('player-model-search-filter').value);
				break;
			case 'favourite-weapons':
				populateWeaponList(document.getElementById('weapon-search-filter').value);
				break;
			case 'favourite-scenarios':
				populateScenarioList(document.getElementById('scenario-search-filter').value);
				break;
			case 'favourite-animations':
				populateAnimationList(document.getElementById('animation-search-filter').value);
				break;
			case 'favourite-propsets':
				populatePropsetList(document.getElementById('propset-search-filter').value);
				break;
			case 'favourite-pickups':
				populatePickupList(document.getElementById('pickup-search-filter').value);
				break;
			case 'favourite-walk-styles':
				populateWalkStyleList(document.getElementById('walk-style-search-filter').value);
				break;
		}
	}));

	document.getElementById('import-export-format').addEventListener('input', function(event) {
		var importButton = document.getElementById('import-db');

		switch (this.value) {
			case 'spooner-db-json':
				importButton.disabled = false;
				break;
			case 'map-editor-xml':
				importButton.disabled = true;
				break;
			case 'propplacer':
				importButton.disabled = true;
				break;
			case 'backup':
				importButton.disabled = false;
				break;
		}
	});

	document.getElementById('properties-clean').addEventListener('click', function(event) {
		sendMessage('cleanPed', {
			handle: currentEntity()
		});
	});

	document.getElementById('properties-scale').addEventListener('input', function(event) {
		sendMessage('setScale', {
			handle: currentEntity(),
			scale: parseFloat(this.value)
		});
	});

	document.getElementById('properties-particle-scale').addEventListener('input', function(event) {
		sendMessage('setParticleScale', {
			handle: currentEntity(),
			scale: parseFloat(this.value)
		});
	});

	document.getElementById('properties-select').addEventListener('click', function(event) {
		sendMessage('selectEntity', {
			handle: currentEntity()
		});
	});

	document.getElementById('properties-clone-ped').addEventListener('click', function(event) {
		sendMessage('clonePed', {
			handle: currentEntity()
		});
	});

	document.getElementById('properties-config-flags').addEventListener('click', function(event) {
		sendMessage('getPedConfigFlags', {
			handle: currentEntity()
		}).then(resp => resp.json()).then(resp => {
			populatePedConfigFlagsList(resp);
			document.getElementById('ped-options-menu').style.display = 'none';
			document.getElementById('config-flags-menu').style.display = 'flex';
		});
	});

	document.getElementById('close-config-flags-menu').addEventListener('click', function(event) {
		document.getElementById('config-flags-menu').style.display = 'none';
		document.getElementById('ped-options-menu').style.display = 'flex';
	});

	document.getElementById('add-config-flag').addEventListener('click', function(event) {
		var flag = parseInt(document.getElementById('config-flag').value);

		sendMessage('setPedConfigFlag', {
			handle: currentEntity(),
			flag: flag,
			value: true
		}).then(resp => resp.json()).then(resp => populatePedConfigFlagsList(resp));
	});

	document.getElementById('animation-stop').addEventListener('click', function(event) {
		sendMessage('stopAnimation', {
			handle: currentEntity()
		});
		stopAnimTimeline();
	});

	document.getElementById('animation-pause').addEventListener('click', function(event) {
		sendMessage('pauseAnimation', { handle: currentEntity() });
	});

	document.getElementById('animation-resume').addEventListener('click', function(event) {
		sendMessage('resumeAnimation', { handle: currentEntity() });
	});

	document.getElementById('animation-time-slider').addEventListener('input', function() {
		sendMessage('setAnimationTime', {
			handle: currentEntity(),
			time: parseFloat(this.value)
		});
	});

	document.getElementById('scenario-stop').addEventListener('click', function(event) {
		sendMessage('clearPedTasks', {
			handle: currentEntity()
		});
	});

	document.getElementById('properties-go-to-waypoint').addEventListener('click', function(event) {
		sendMessage('goToWaypoint', {
			handle: currentEntity()
		});
	});

	document.getElementById('properties-go-to-entity').addEventListener('click', function(event) {
		var handle = currentEntity();
		openEntitySelect('ped-options-menu', function(entity) {
			sendMessage('pedGoToEntity', {
				handle: handle,
				entity: entity
			});
		}, handle);
	});

	document.getElementById('properties-focus').addEventListener('click', function(event) {
		sendMessage('focusEntity', {
			handle: currentEntity()
		});
	});

	document.getElementById('copy-position').addEventListener('click', function(event) {
		var x = document.getElementById('properties-x').value;
		var y = document.getElementById('properties-y').value;
		var z = document.getElementById('properties-z').value;

		copyToClipboard(formatNumber(x) + ', ' + formatNumber(y) + ', ' + formatNumber(z));
	});

	document.getElementById('copy-rotation').addEventListener('click', function(event) {
		var p = document.getElementById('properties-pitch').value;
		var r = document.getElementById('properties-roll').value;
		var y = document.getElementById('properties-yaw').value;

		copyToClipboard(formatNumber(p) + ', ' + formatNumber(r) + ', ' + formatNumber(y));
	});

	document.getElementById('copy-attachment-position').addEventListener('click', function(event) {
		var x = document.getElementById('attachment-x').value;
		var y = document.getElementById('attachment-y').value;
		var z = document.getElementById('attachment-z').value;

		copyToClipboard(formatNumber(x) + ', ' + formatNumber(y) + ', ' + formatNumber(z))
	});

	document.getElementById('copy-entity-id').addEventListener('click', function(event) {
		copyToClipboard(event.target.getAttribute('data-entity-id'));
	});

	document.getElementById('copy-net-id').addEventListener('click', function(event) {
		copyToClipboard(event.target.getAttribute('data-net-id'));
	});

	document.getElementById('copy-model-name').addEventListener('click', function(event) {
		copyToClipboard(event.target.getAttribute('data-model-name'))
	});

	document.getElementById('copy-attachment-rotation').addEventListener('click', function(event) {
		var p = document.getElementById('attachment-pitch').value;
		var r = document.getElementById('attachment-roll').value;
		var y = document.getElementById('attachment-yaw').value;

		copyToClipboard(formatNumber(p) + ', ' + formatNumber(r) + ', ' + formatNumber(y));
	});

	document.getElementById('copy-attachment-settings').addEventListener('click', function(event) {
		sendMessage('getAttachmentSettings', {
			handle: currentEntity()
		}).then(resp => resp.json()).then(resp => {
			copyToClipboard(resp.value);
		});
	});

	document.getElementById('copy-animation-settings').addEventListener('click', function(event) {
		sendMessage('getAnimationSettings', {
			handle: currentEntity()
		}).then(resp => resp.json()).then(resp => {
			copyToClipboard(resp.value);
		});
	});

	document.getElementById('add-to-db-btn').addEventListener('click', function(event) {
		document.getElementById('object-database').style.display = 'none';
		document.getElementById('add-to-db-menu').style.display = 'flex';
	});

	document.getElementById('add-to-db-menu-close').addEventListener('click', function(event) {
		document.getElementById('add-to-db-menu').style.display = 'none';
		document.getElementById('object-database').style.display = 'flex';
	});

	document.getElementById('add-custom-entity-btn').addEventListener('click', function(event) {
		sendMessage('addCustomEntityToDatabase', {
			handle: parseInt(document.getElementById('custom-entity-handle').value)
		}).then(resp => resp.json()).then(resp => {
			document.getElementById('add-to-db-menu').style.display = 'none';
			openDatabase(resp);
		});
	});

	// Offset tool
	document.getElementById('offset-select-reference').addEventListener('click', function(event) {
		var handle = currentEntity();
		openEntitySelect('properties-menu', function(entity) {
			startOffsetPolling(handle, entity);
		}, handle);
	});

	document.getElementById('offset-clear').addEventListener('click', function(event) {
		clearOffsetReference();
	});

	document.getElementById('offset-copy-local').addEventListener('click', function(event) {
		var x = document.getElementById('offset-local-x').value;
		var y = document.getElementById('offset-local-y').value;
		var z = document.getElementById('offset-local-z').value;
		copyToClipboard(x + ', ' + y + ', ' + z);
	});

	document.getElementById('offset-copy-all').addEventListener('click', function(event) {
		var lx = document.getElementById('offset-local-x').value;
		var ly = document.getElementById('offset-local-y').value;
		var lz = document.getElementById('offset-local-z').value;
		var p = document.getElementById('offset-pitch').value;
		var r = document.getElementById('offset-roll').value;
		var yw = document.getElementById('offset-yaw').value;
		var d = document.getElementById('offset-distance').innerText;
		copyToClipboard('Local: ' + lx + ', ' + ly + ', ' + lz + ' | Rot: ' + p + ', ' + r + ', ' + yw + ' | Distance: ' + d);
	});

	document.getElementById('properties-attack').addEventListener('click', function(event) {
		let handle = currentEntity();

		openEntitySelect('ped-options-menu', function(entity) {
			sendMessage('attackPed', {
				handle: handle,
				ped: entity
			});
		}, handle);
	});

	sendMessage('loaded', {});
});

function test() {
	// Uncomment coresponding menu for testing

	document.querySelector('#properties-menu').style.display = 'flex';
	// document.getElementById('attachment-options-menu').style.display = 'flex';
	// document.querySelector('#animation-menu').style.display = 'flex';
}
// Uncomment for testing in browser
// setTimeout(() => {
// 	test();
// }, 50);
