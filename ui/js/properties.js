// ============================================================================
// spooner :: ui/js/properties.js
// Entity database rows, entity display names, and the entity properties menu
//
// Split from ui/script.js. Loaded as a classic <script> in ui/index.html in the
// original source order, so all files share one global scope (behaviour preserved).
// ============================================================================

function deleteEntity(object) {
	var handle = object.getAttribute('data-handle');

	object.remove();

	sendMessage('deleteEntity', {
		handle: parseInt(handle)
	}).then(resp => resp.json()).then(resp => openDatabase(resp));
}

function entityDisplayName(entity, props) {
	if (props.exists) {
		if (props.netId) {
			if (props.playerName) {
				return `${entity.toString()} [${props.netId.toString()}] ${props.name} (${props.playerName})`;
			} else {
				return `${entity.toString()} [${props.netId.toString()}] ${props.name}`;
			}
		} else {
			return `${entity.toString()} ${props.name}`
		}
	} else {
		return `(Invalid) ${entity.toString()} ${props.name}`
	}
}

function openDatabase(data) {
	var objectList = document.querySelector('#object-database-list');
	var database = JSON.parse(data.database);

	var keys = Object.keys(database);

	var totalEntities = keys.length;
	var totalPeds = 0;
	var totalVehicles = 0;
	var totalObjects = 0;
	var totalNetworked = 0;

	objectList.innerHTML = '';

	keys.forEach(function(handle) {
		var entityId = parseInt(handle);

		switch (database[handle].type) {
			case 1:
				++totalPeds;
				break;
			case 2:
				++totalVehicles;
				break;
			case 3:
				++totalObjects;
				break;
		}

		if (database[handle].netId) {
			++totalNetworked;
		}

		var div = document.createElement('div');

		if (database[handle].isSelf) {
			div.className = 'object self';
		} else if (!database[handle].exists) {
			div.className = 'object invalid';
		} else {
			div.className = 'object'
		}

		div.innerHTML = entityDisplayName(entityId, database[handle]);

		div.setAttribute('data-handle', handle);
		div.addEventListener('click', function(event) {
			document.querySelector('#object-database').style.display = 'none';
			sendMessage('openPropertiesMenuForEntity', {
				entity: entityId
			});
		});
		div.addEventListener('contextmenu', function(event) {
			deleteEntity(this);
		});
		objectList.appendChild(div);
	});

	document.getElementById('object-database-total-entities').innerHTML = keys.length;
	document.getElementById('object-database-total-peds').innerHTML = totalPeds;
	document.getElementById('object-database-total-vehicles').innerHTML = totalVehicles;
	document.getElementById('object-database-total-objects').innerHTML = totalObjects;
	document.getElementById('object-database-total-networked').innerHTML = totalNetworked;

	document.querySelector('#object-database').style.display = 'flex';
}

function closeDatabase() {
	document.querySelector('#object-database').style.display = 'none';

	sendMessage('closeDatabase', {});
}

function removeAllFromDatabase() {
	sendMessage('removeAllFromDatabase', {});

	closeDatabase()
}

function setFieldIfInactive(id, value) {
	var field = document.getElementById(id);

	if (document.activeElement != field) {
		field.value = value;
	}
}

function updatePropertiesMenu(data) {
	var properties = JSON.parse(data.properties);

	document.querySelectorAll('.player-property').forEach(e => e.style.display = 'none');
	document.querySelectorAll('.ped-property').forEach(e => e.style.display = 'none');
	document.querySelectorAll('.vehicle-property').forEach(e => e.style.display = 'none');
	document.querySelectorAll('.object-property').forEach(e => e.style.display = 'none');
	document.querySelectorAll('.particle-property').forEach(e => e.style.display = 'none');

	switch (properties.type) {
		case 1:
			document.querySelector('#properties-menu-entity-type').innerHTML = 'ped';
			document.querySelectorAll('.ped-property').forEach(e => e.style.display = 'block');
			break;
		case 2:
			document.querySelector('#properties-menu-entity-type').innerHTML = 'vehicle';
			document.querySelectorAll('.vehicle-property').forEach(e => e.style.display = 'block');
			break;
		case 3:
			document.querySelector('#properties-menu-entity-type').innerHTML = 'object';
			document.querySelectorAll('.object-property').forEach(e => e.style.display = 'block');
			break;
		case 4:
			document.querySelector('#properties-menu-entity-type').innerHTML = 'propset';
			break;
		case 5:
			document.querySelector('#properties-menu-entity-type').innerHTML = 'pickup';
			break;
		default:
			document.querySelector('#properties-menu-entity-type').innerHTML = 'entity';
			break;
	}

	if (properties.playerName) {
		document.querySelectorAll('.player-property').forEach(e => e.style.display = 'block');
	}

	if (properties.particle) {
		document.querySelectorAll('.particle-property').forEach(e => e.style.display = 'block');
		setFieldIfInactive('properties-particle-scale', properties.particle.scale);
	}

	var entity = document.querySelector('#properties-menu-entity-id');
	entity.setAttribute('data-handle', data.entity);
	if (properties.netId) {
		if (properties.playerName) {
			entity.innerHTML = data.entity.toString() + ' [' + properties.netId.toString() + '] (' + properties.playerName + ')';
		} else {
			entity.innerHTML = data.entity.toString() + ' [' + properties.netId.toString() + ']';
		}
	} else {
		entity.innerHTML = data.entity.toString();
	}

	document.querySelector('#copy-entity-id').setAttribute('data-entity-id', data.entity.toString());
	if (properties.netId) {
		document.querySelector('#copy-net-id').setAttribute('data-net-id', properties.netId.toString());
	} else {
		document.querySelector('#copy-net-id').setAttribute('data-net-id', '');
	}
	document.querySelector('#copy-model-name').setAttribute('data-model-name', properties.name);

	setFieldIfInactive('properties-x', properties.x);
	setFieldIfInactive('properties-y', properties.y);
	setFieldIfInactive('properties-z', properties.z);

	setFieldIfInactive('properties-pitch', properties.pitch);
	setFieldIfInactive('properties-roll', properties.roll);
	setFieldIfInactive('properties-yaw', properties.yaw);

	if (data.inDb) {
		document.querySelector('#properties-add-to-db').style.display = 'none';
		document.querySelector('#properties-remove-from-db').style.display = 'block';
	} else {
		document.querySelector('#properties-add-to-db').style.display = 'block';
		document.querySelector('#properties-remove-from-db').style.display = 'none';
	}

	setFieldIfInactive('properties-health', properties.health);

	setFieldIfInactive('properties-outfit', properties.outfit);

	if (properties.netId) {
		document.getElementById('properties-request-control').disabled = data.hasNetworkControl || properties.type == 0;
		document.getElementById('properties-register-as-networked').style.display = 'none';
		document.getElementById('properties-request-control').style.display = 'block';
	} else {
		document.getElementById('properties-request-control').style.display = 'none';
		document.getElementById('properties-register-as-networked').style.display = 'block';
	}

	if (properties.isFrozen) {
		document.getElementById('properties-freeze').style.display = 'none';
		document.getElementById('properties-unfreeze').style.display = 'block';
	} else {
		document.getElementById('properties-unfreeze').style.display = 'none';
		document.getElementById('properties-freeze').style.display = 'block';
	}

	if (properties.isInGroup) {
		document.querySelector('#properties-add-to-group').style.display = 'none';
		document.querySelector('#properties-remove-from-group').style.display = 'block';
	} else {
		document.querySelector('#properties-remove-from-group').style.display = 'none';
		document.querySelector('#properties-add-to-group').style.display = 'block';
	}

	if (properties.collisionDisabled) {
		document.querySelector('#properties-collision-off').style.display = 'none';
		document.querySelector('#properties-collision-on').style.display = 'block';
	} else {
		document.querySelector('#properties-collision-on').style.display = 'none';
		document.querySelector('#properties-collision-off').style.display = 'block';
	}

	if (properties.lightsIntensity) {
		setFieldIfInactive('properties-lights-intensity', properties.lightsIntensity);
	} else {
		setFieldIfInactive('properties-lights-intensity', 0);
	}

	if (properties.lightsColour) {
		setFieldIfInactive('properties-lights-red', properties.lightsColour.red);
		setFieldIfInactive('properties-lights-green', properties.lightsColour.green);
		setFieldIfInactive('properties-lights-blue', properties.lightsColour.blue);
	} else {
		setFieldIfInactive('properties-lights-red', 0);
		setFieldIfInactive('properties-lights-green', 0);
		setFieldIfInactive('properties-lights-blue', 0);
	}

	if (properties.lightsType) {
		setFieldIfInactive('properties-lights-type', properties.lightsType);
	} else {
		setFieldIfInactive('properties-lights-type', 0);
	}

	if (properties.isVisible) {
		document.getElementById('properties-visible').style.display = 'none';
		document.getElementById('properties-invisible').style.display = 'block';
	} else {
		document.getElementById('properties-invisible').style.display = 'none';
		document.getElementById('properties-visible').style.display = 'block';
	}

	if (properties.scale) {
		setFieldIfInactive('properties-scale', properties.scale);
	} else {
		setFieldIfInactive('properties-scale', 1.0)
	}
}

function sendUpdatePropertiesMenuMessage(handle, open) {
	sendMessage('updatePropertiesMenu', {
		handle: handle
	}).then(resp => resp.json()).then(function(resp){
		updatePropertiesMenu(resp);

		if (open) {
			document.querySelector('#properties-menu').style.display = 'flex';
		}
	});
}

function openPropertiesMenu(data) {
	sendUpdatePropertiesMenuMessage(data.entity, true);

	if (propertiesMenuUpdate) {
		clearInterval(propertiesMenuUpdate);
		propertiesMenuUpdate = null;
	}

	propertiesMenuUpdate = setInterval(function() {
		sendUpdatePropertiesMenuMessage(data.entity, false);
	}, 500);
}

function closePropertiesMenu(loseFocus) {
	document.querySelector('#properties-menu').style.display = 'none';
	document.querySelector('#ped-options-menu').style.display = 'none';
	document.querySelector('#vehicle-options-menu').style.display = 'none';

	clearInterval(propertiesMenuUpdate);
	clearOffsetReference();

	if (loseFocus) {
		sendMessage('closePropertiesMenu', {});
	}
}

// Close the properties menu with Tab (the same key that opens it)
document.addEventListener('keydown', function(event) {
	if (event.key === 'Tab' && document.querySelector('#properties-menu').style.display === 'flex') {
		event.preventDefault();
		closePropertiesMenu(true);
	}
});

// Escape on the spawn (F) menu: go back one level, or close it from the category list.
// The entity sub-menus (peds/vehicles/objects/propsets/pickups) handle their own
// Escape -> Back; here we cover the category list and the custom Saved Peds menu.
document.addEventListener('keydown', function(event) {
	if (event.key !== 'Escape') {
		return;
	}

	if (document.querySelector('#saved-peds-menu').style.display === 'flex') {
		// Let an in-progress rename input cancel itself instead of leaving the menu
		if (document.activeElement && document.activeElement.classList.contains('saved-ped-rename-input')) {
			return;
		}
		event.preventDefault();
		closeSavedPedsMenu(false);
		return;
	}

	if (document.querySelector('#mp-peds-menu').style.display === 'flex') {
		if (document.activeElement && document.activeElement.classList.contains('saved-ped-rename-input')) {
			return;
		}
		event.preventDefault();
		closeMpPedsMenu(false);
		return;
	}

	if (document.querySelector('#mp-custom-menu').style.display === 'flex') {
		event.preventDefault();
		closeCustomMpPedMenu();
		return;
	}

	if (document.querySelector('#placed-particles-menu').style.display === 'flex') {
		event.preventDefault();
		closePlacedParticlesMenu();
		return;
	}

	if (document.querySelector('#spawn-menu').style.display === 'flex') {
		event.preventDefault();
		closeSpawnMenu();
	}
});

// Escape on the properties (Tab) menu tree: go back one level by triggering the
// menu's own Back/Close button, so all of its side effects are preserved.
// Menus are ordered child-most first; only one is visible at a time, so the first
// visible match is the one to close.
var propertiesEscapeMenus = [
	{ menu: 'import-export-db', back: 'import-export-db-close' },
	{ menu: 'save-load-db-menu', back: 'save-load-db-menu-close-btn' },
	{ menu: 'help-menu', back: 'help-menu-close-btn' },
	{ menu: 'config-flags-menu', back: 'close-config-flags-menu' },
	{ menu: 'walk-style-menu', back: 'walk-style-menu-close' },
	{ menu: 'weapon-menu', back: 'weapon-menu-close' },
	{ menu: 'scenario-menu', back: 'scenario-menu-close' },
	{ menu: 'emotion-menu', back: 'emotion-menu-close' },
	{ menu: 'player-model-menu', back: 'player-model-menu-close-btn' },
	{ menu: 'animation-list-menu', back: 'animation-list-menu-close' },
	{ menu: 'animation-menu', back: 'animation-menu-close' },
	{ menu: 'lights-options-menu', back: 'lights-options-menu-close' },
	{ menu: 'attachment-options-menu', back: 'attachment-options-menu-close' },
	{ menu: 'ped-options-menu', back: 'ped-options-menu-close' },
	{ menu: 'vehicle-options-menu', back: 'vehicle-options-menu-close' },
	{ menu: 'animprops-menu', back: 'animprops-menu-back' },
	{ menu: 'properties-menu', back: 'properties-menu-close-btn' }
];

document.addEventListener('keydown', function(event) {
	if (event.key !== 'Escape') {
		return;
	}

	// Entity select sub-menu (Look At / Attach / Go To...) -> its dynamic Back button
	var entitySelect = document.getElementById('entity-select-menu');
	if (entitySelect && entitySelect.style.display === 'flex') {
		var backBtn = entitySelect.querySelector('button');
		if (backBtn) {
			event.preventDefault();
			backBtn.click();
		}
		return;
	}

	for (var i = 0; i < propertiesEscapeMenus.length; i++) {
		var entry = propertiesEscapeMenus[i];
		var menu = document.getElementById(entry.menu);

		if (menu && menu.style.display === 'flex') {
			var btn = document.getElementById(entry.back);
			if (btn) {
				event.preventDefault();
				btn.click();
			}
			return;
		}
	}
});

