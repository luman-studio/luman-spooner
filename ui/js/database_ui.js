// ============================================================================
// spooner :: ui/js/database_ui.js
// Save/load database menus, attach-to menu, permissions, entity-select, controls, ped config flags
//
// Split from ui/script.js. Loaded as a classic <script> in ui/index.html in the
// original source order, so all files share one global scope (behaviour preserved).
// ============================================================================

function loadDatabase(name) {
	var relative = document.querySelector('#load-db-relative').checked;
	var replace = document.querySelector('#replace-db').checked;

	sendMessage('loadDb', {
		name: name,
		relative: relative,
		replace: replace
	});
}

function updateDbList(data) {
	var databaseNames = JSON.parse(data);
	var dbList = document.querySelector('#db-list');

	dbList.innerHTML = '';

	databaseNames.forEach(function(name) {
		var div = document.createElement('div');
		div.className = 'database';
		div.innerHTML = name;
		div.addEventListener('click', function(event) {
			loadDatabase(this.innerHTML);
		});
		div.addEventListener('contextmenu', function(event) {
			sendMessage('deleteDb', {
				name: this.innerHTML
			});
			this.remove();
		});
		dbList.appendChild(div);
	});
}

function openSaveLoadDbMenu(databaseNames) {
	updateDbList(databaseNames)
	document.querySelector('#save-load-db-menu').style.display = 'flex';
}

function closeSaveLoadDbMenu() {
	document.querySelector('#save-load-db-menu').style.display = 'none';
	sendMessage('closeSaveLoadDbMenu', {});
}

function goToEntity(handle) {
	sendMessage('goToEntity', {
		handle: handle
	});
}

function openHelpMenu() {
	document.querySelector('#help-menu').style.display = 'flex';
	document.querySelector('#hud').style.display = 'none';
}

function closeHelpMenu() {
	document.querySelector('#help-menu').style.display = 'none';
	document.querySelector('#hud').style.display = 'block';
	sendMessage('closeHelpMenu', {});
}

function getIntoVehicle(handle) {
	sendMessage('getIntoVehicle', {
		handle: handle
	});
}

function attachTo(fromEntity, toEntity) {
	var boneName = document.getElementById('attachment-bone-name').value;
	var boneIndex = parseInt(document.getElementById('attachment-bone-index').value);

	sendMessage('attachTo', {
		from: fromEntity,
		to: toEntity,
		bone: boneName == '' ? boneIndex : boneName,
		x: parseFloat(document.getElementById('attachment-x').value),
		y: parseFloat(document.getElementById('attachment-y').value),
		z: parseFloat(document.getElementById('attachment-z').value),
		pitch: parseFloat(document.getElementById('attachment-pitch').value),
		roll: parseFloat(document.getElementById('attachment-roll').value),
		yaw: parseFloat(document.getElementById('attachment-yaw').value),
		keepPos: document.getElementById('attachment-keep-pos').checked,
		useSoftPinning: document.getElementById('attachment-use-soft-pinning').checked,
		collision: document.getElementById('attachment-collision').checked,
		vertex: parseInt(document.getElementById('attachment-vertex').value),
		fixedRot: document.getElementById('attachment-fixed-rot').checked
	});
	sendMessage('getDatabase', {handle: fromEntity}).then(resp => resp.json()).then(resp => openAttachToMenu(fromEntity, resp));
}

function openAttachToMenu(fromEntity, data) {
	var properties = JSON.parse(data.properties);
	var database = JSON.parse(data.database);

	var list = document.getElementById('attach-to-list');

	list.innerHTML = '';

	var addTo = true;

	Object.keys(database).forEach(function(handle) {
		var toEntity = parseInt(handle);

		if (toEntity == fromEntity) {
			return;
		}

		var div = document.createElement('div');

		if (properties.attachment.to == handle) {
			div.className = 'object selected';
			addTo = false;
		} else {
			div.className = 'object';
		}

		div.innerHTML = entityDisplayName(toEntity, database[handle]);

		div.setAttribute('data-handle', handle);
		div.addEventListener('click', function(event) {
			document.getElementById('attachment-options-menu').style.display = 'none';
			attachTo(fromEntity, toEntity);
		});
		list.appendChild(div);
	});

	if (addTo && properties.attachment.to) {
		var div = document.createElement('div');
		div.className = 'object selected';
		if (database[properties.attachment.to]) {
			div.innerHTML = database[properties.attachment.to].name;
		} else {
			div.innerHTML = properties.attachment.to.toString();
		}
		div.addEventListener('click', function(event) {
			document.getElementById('attachment-options-menu').style.display = 'none';
			attachTo(fromEntity, properties.attachment.to);
		});
		list.appendChild(div);
	}

	if (typeof properties.attachment.bone == 'number') {
		document.getElementById('attachment-bone-name').value = '';
		document.getElementById('attachment-bone-index').value = properties.attachment.bone;
	} else {
		document.getElementById('attachment-bone-index').value = '';
		document.getElementById('attachment-bone-name').value = properties.attachment.bone;
	}

	document.getElementById('attachment-x').value = properties.attachment.x;
	document.getElementById('attachment-y').value = properties.attachment.y;
	document.getElementById('attachment-z').value = properties.attachment.z;
	document.getElementById('attachment-pitch').value = properties.attachment.pitch;
	document.getElementById('attachment-roll').value = properties.attachment.roll;
	document.getElementById('attachment-yaw').value = properties.attachment.yaw;
	document.getElementById('attachment-use-soft-pinning').value = properties.attachment.useSoftPinning;
	document.getElementById('attachment-collision').value = properties.attachment.collision;
	document.getElementById('attachment-vertex').value = properties.attachment.vertex;
	document.getElementById('attachment-fixed-rot').value = properties.attachment.fixedRot;

	if (properties.attachment.to) {
		document.getElementById('attachment-options-detach').style.display = 'block';
	} else {
		document.getElementById('attachment-options-detach').style.display = 'none';
	}

	document.getElementById('attachment-options-menu').style.display = 'flex';
}

function updatePermissions(data) {
	console.log('Permissions loaded');
	
	var permissions = JSON.parse(data.permissions);

	document.getElementById('spawn-menu-peds').disabled = !permissions.spawn.ped;
	document.getElementById('spawn-menu-vehicles').disabled = !permissions.spawn.vehicle;
	document.getElementById('spawn-menu-objects').disabled = !permissions.spawn.object;
	document.getElementById('spawn-menu-propsets').disabled = !permissions.spawn.propset;
	document.getElementById('spawn-menu-pickups').disabled = !permissions.spawn.pickup;
	document.getElementById('spawn-menu-saved-peds').disabled = !permissions.spawn.ped;
	document.getElementById('spawn-menu-mp-peds').disabled = !permissions.spawn.ped;
	document.getElementById('mp-peds-create-custom').disabled = !permissions.spawn.ped;
	document.getElementById('spawn-menu-particles').disabled = !permissions.spawn.particle;
	document.querySelectorAll('.spawn-by-name').forEach(e => e.disabled = !permissions.spawn.byName);

	document.getElementById('properties-freeze').disabled = !permissions.properties.freeze;
	document.getElementById('properties-unfreeze').disabled = !permissions.properties.freeze;
	document.getElementById('properties-x').disabled = !permissions.properties.position;
	document.getElementById('properties-y').disabled = !permissions.properties.position;
	document.getElementById('properties-z').disabled = !permissions.properties.position;
	document.getElementById('properties-place-here').disabled = !permissions.properties.position;
	document.getElementById('properties-goto').disabled = !permissions.properties.goTo;
	document.getElementById('properties-pitch').disabled = !permissions.properties.rotation;
	document.getElementById('properties-roll').disabled = !permissions.properties.rotation;
	document.getElementById('properties-yaw').disabled = !permissions.properties.rotation;
	document.getElementById('properties-reset-rotation').disabled = !permissions.properties.rotation;
	document.getElementById('properties-health').disabled = !permissions.properties.health;
	document.getElementById('properties-invincible-on').disabled = !permissions.properties.invincible;
	document.getElementById('properties-invincible-off').disabled = !permissions.properties.invincible;
	document.getElementById('properties-visible').disabled = !permissions.properties.visible;
	document.getElementById('properties-invisible').disabled = !permissions.properties.visible;
	document.getElementById('properties-gravity-on').disabled = !permissions.properties.gravity;
	document.getElementById('properties-gravity-off').disabled = !permissions.properties.gravity;
	document.getElementById('properties-collision-off').disabled = !permissions.properties.collision;
	document.getElementById('properties-collision-on').disabled = !permissions.properties.collision;
	document.getElementById('properties-clone').disabled = !permissions.properties.clone;
	document.getElementById('properties-attach').disabled = !permissions.properties.attachments;
	document.getElementById('properties-player-model').disabled = !permissions.properties.ped.changeModel;
	document.getElementById('properties-outfit').disabled = !permissions.properties.ped.outfit;
	document.getElementById('properties-customize-ped').disabled = !permissions.properties.ped.outfit;
	document.getElementById('properties-add-to-group').disabled = !permissions.properties.ped.group;
	document.getElementById('properties-remove-from-group').disabled = !permissions.properties.ped.group;
	document.getElementById('properties-scenario').disabled = !permissions.properties.ped.scenario;
	document.getElementById('properties-animation').disabled = !permissions.properties.ped.animation;
	document.getElementById('properties-clear-ped-tasks').disabled = !permissions.properties.ped.clearTasks;
	document.getElementById('properties-clear-ped-tasks-immediately').disabled = !permissions.properties.ped.clearTasks;
	document.getElementById('properties-give-weapon').disabled = !permissions.properties.ped.weapon;
	document.getElementById('properties-holster-weapon').disabled = !permissions.properties.ped.weapon;
	document.getElementById('properties-remove-all-weapons').disabled = !permissions.properties.ped.weapon;
	document.getElementById('properties-set-on-mount').disabled = !permissions.properties.ped.mount;
	document.getElementById('properties-resurrect-ped').disabled = !permissions.properties.ped.resurrect;
	document.getElementById('properties-ai-on').disabled = !permissions.properties.ped.ai;
	document.getElementById('properties-ai-off').disabled = !permissions.properties.ped.ai;
	document.getElementById('properties-knock-off-props').disabled = !permissions.properties.ped.knockOffProps;
	document.getElementById('properties-clone-ped').disabled = !permissions.properties.clone;
	document.getElementById('properties-clone-to-target').disabled = !permissions.properties.ped.cloneToTarget;
	document.getElementById('properties-repair-vehicle').disabled = !permissions.properties.vehicle.repair;
	document.getElementById('properties-get-in').disabled = !permissions.properties.vehicle.getin
	document.getElementById('properties-engine-on').disabled = !permissions.properties.vehicle.engine
	document.getElementById('properties-engine-off').disabled = !permissions.properties.vehicle.engine
	document.getElementById('properties-vehicle-lights-on').disabled = !permissions.properties.vehicle.lights;
	document.getElementById('properties-vehicle-lights-off').disabled = !permissions.properties.vehicle.lights;
	document.getElementById('properties-register-as-networked').disabled = !permissions.properties.registerAsNetworked;
	document.getElementById('add-to-db-btn').disabled = permissions.maxEntities || !permissions.modify.other;

	// 
	document.getElementById('properties-physics-push').disabled = false;
}

function currentEntity() {
	return parseInt(document.querySelector('#properties-menu-entity-id').getAttribute('data-handle'));
}

function openEntitySelect(menuId, onEntitySelect, ignoreEntity) {
	var menu = document.getElementById(menuId);

	var entitySelect = document.getElementById('entity-select-menu');
	entitySelect.innerHTML = '';

	var entitySelectClose = document.createElement('button');
	entitySelectClose.innerHTML = 'Back';
	entitySelectClose.addEventListener('click', event => {
		entitySelect.style.display = 'none';
		menu.style.display = 'flex';
	});

	var entitySelectList = document.createElement('div');
	entitySelectList.className = 'list';

	sendMessage('getDatabase', {}).then(resp => resp.json()).then(resp => {
		var database = JSON.parse(resp.database);

		Object.keys(database).forEach(key => {
			var handle = parseInt(key);

			if (handle != ignoreEntity) {
				var div = document.createElement('div');
				div.className = 'object';

				div.innerHTML = entityDisplayName(handle, database[key]);

				div.addEventListener('click', event => {
					onEntitySelect(handle);
					entitySelect.style.display = 'none';
					menu.style.display = 'flex';
				});

				entitySelectList.appendChild(div);
			}
		});

		entitySelect.appendChild(entitySelectList);
		entitySelect.appendChild(entitySelectClose);

		menu.style.display = 'none';
		entitySelect.style.display = 'flex';
	});
}

function showControls() {
	document.getElementById('hud').style.display = 'flex';
}

function hideControls() {
	document.getElementById('hud').style.display = 'none';
}

function copyCameraToClipboard(data) {
	copyToClipboard(`SetCamCoord(cam, ${data.camX}, ${data.camY}, ${data.camZ}) SetCamRot(cam, ${data.camRotX}, ${data.camRotY}, ${data.camRotZ})`)
}

function populatePedConfigFlagsList(flags) {
	var configFlagsList = document.getElementById('config-flags-list');

	configFlagsList.innerHTML = '';

	Object.keys(flags).forEach(key => {
		var flag = flags[key];

		var div = document.createElement('div');
		if (flag.value) {
			div.className = 'config-flag on';
		} else {
			div.className = 'config-flag off';
		}

		var flagDiv = document.createElement('div');
		flagDiv.className = 'config-flag-number';
		flagDiv.innerHTML = key;

		var descrDiv = document.createElement('div');
		descrDiv.className = 'config-flag-descr';
		descrDiv.innerHTML = flag.descr;

		var setDiv = document.createElement('div');
		setDiv.className = 'config-flag-set';

		var setButton = document.createElement('button');
		if (flag.value) {
			setButton.innerHTML = '<i class="fas fa-toggle-on"></i>';
			setButton.addEventListener('click', event => {
				sendMessage('setPedConfigFlag', {
					handle: currentEntity(),
					flag: parseInt(key),
					value: false
				}).then(resp => resp.json()).then(resp => populatePedConfigFlagsList(resp));
			});
		} else {
			setButton.innerHTML = '<i class="fas fa-toggle-off"></i>';
			setButton.addEventListener('click', event => {
				sendMessage('setPedConfigFlag', {
					handle: currentEntity(),
					flag: parseInt(key),
					value: true
				}).then(resp => resp.json()).then(resp => populatePedConfigFlagsList(resp));
			});
		}

		setDiv.appendChild(setButton);

		div.appendChild(flagDiv);
		div.appendChild(descrDiv);
		div.appendChild(setDiv);

		configFlagsList.appendChild(div);
	});
}

