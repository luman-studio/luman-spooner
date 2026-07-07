// ============================================================================
// spooner :: ui/js/hud.js
// sendMessage/clipboard helpers, spooner HUD show/hide/update, and open/close of each spawn menu
//
// Split from ui/script.js. Loaded as a classic <script> in ui/index.html in the
// original source order, so all files share one global scope (behaviour preserved).
// ============================================================================


var propertiesMenuUpdate;

// Animation copy/paste buffer (set by Copy Animation, used by Paste Animation)
var copiedAnimation = null;

// Scenario copy/paste buffer (set by Copy Scenario, used by Paste Scenario)
var copiedScenario = null;

const favouriteTypes = [
	'peds',
	'vehicles',
	'objects',
	'propsets',
	'pickups',
	'particles',
	'scenarios',
	'animations',
	'weapons',
	'walkStyles',
	'playerModels'
];

var favourites = {};

function sendMessage(name, params) {
	if (typeof GetParentResourceName !== "undefined") { 
		return fetch('https://' + GetParentResourceName() + '/' + name, {
			method: 'POST',
			headers: {
				'Content-Type': 'application/json'
			},
			body: JSON.stringify(params)
		});
	} else {

		return new Promise((resolve) => {
			// Simulate a server response
			resolve({
				json: () => Promise.resolve({ 
					peds: "[]",
					favourites: "[]",
					vehicles: "[]",
					objects: "[]",
					scenarios: "[]",
					weapons: "[]",
					animations: "[]",
					propsets: "[]",
					pickups: "[]",
					particles: "[]",
					bones: "[]",
					walkStyleBases: "[]",
					walkStyles: "[]",
					adjustSpeed: 0,
					rotateSpeed: 0,
				}) // Mock response
			});
		});
	}
}

function copyToClipboard(text) {
	var e = document.createElement('textarea');
	e.textContent = text;
	document.body.appendChild(e);

	var selection = document.getSelection();
	selection.removeAllRanges();

	e.select();
	document.execCommand('copy');

	selection.removeAllRanges();
	e.remove();

	notify('Copied to clipboard! Use Ctrl + V to have it.');
}

function showSpoonerHud() {
	document.querySelector('#hud').style.display = 'block';
	isSpoonerHudOpened = true;
}

function hideSpoonerHud() {
	document.querySelector('#hud').style.display = 'none';
	closeAllMenus();
	isSpoonerHudOpened = false;
}

function updateSpoonerHud(data) {
	var crosshair = document.querySelector('#crosshair');

	if (data.attachedEntity) {
		crosshair.className = 'attached';
	} else if (data.entity) {
		crosshair.className = 'active';
	} else {
		crosshair.className = 'inactive';
	}

	var entityInfo = document.querySelector('#entity-info');
	var entityId = document.querySelector('#entity-id');
	var entityNetId = document.querySelector('#entity-net-id');
	
	if (data.entity) {
		if (data.netId) {
			entityId.innerHTML = data.entity.toString() + ' [' + data.netId.toString() + ']';
		} else {
			entityId.innerHTML = data.entity.toString();
		}
		entityInfo.style.display = 'block';

		document.getElementById('basic-controls').style.display = 'none';
		document.getElementById('entity-controls').style.display = 'flex';
	} else {
		entityInfo.style.display = 'none';

		document.getElementById('entity-controls').style.display = 'none';
		document.getElementById('basic-controls').style.display = 'flex';
	}

	var spawnInfo = document.querySelector('#spawn-info');
	var spawnId = document.querySelector('#spawn-id');

	if (data.currentSpawn) {
		spawnId.innerHTML = data.currentSpawn;
		spawnInfo.style.display = 'block';
	} else {
		spawnInfo.style.display = 'none';
	}

	if (data.speedMode == 0) {
		document.querySelector('#speed').innerHTML = `[${data.speed}]`
	} else {
		document.querySelector('#speed').innerHTML = data.speed;
	}

	switch(data.adjustMode) {
		case 0:
			document.querySelector('#adjust-mode').innerHTML = 'X';
			break;
		case 1:
			document.querySelector('#adjust-mode').innerHTML = 'Y';
			break;
		case 2:
			document.querySelector('#adjust-mode').innerHTML = 'Z';
			break;
		case 3:
			document.querySelector('#adjust-mode').innerHTML = 'Rotate';
			break;
		case 4:
			document.querySelector('#adjust-mode').innerHTML = 'Free';
			break;
		case 5:
			document.querySelector('#adjust-mode').innerHTML = 'Off';
			break;

	}

	switch(data.rotateMode) {
		case 0:
			document.querySelector('#rotate-mode').innerHTML = 'Pitch';
			break;
		case 1:
			document.querySelector('#rotate-mode').innerHTML = 'Roll';
			break;
		case 2:
			document.querySelector('#rotate-mode').innerHTML = 'Yaw';
			break;
	}

	if (data.adjustMode == 4) {
		document.querySelector('#place-on-ground-container').style.display = 'none';
	} else {
		document.querySelector('#place-on-ground-container').style.display = 'block';
	}

	if (data.placeOnGround) {
		document.querySelector('#place-on-ground').innerHTML = 'On';
	} else {
		document.querySelector('#place-on-ground').innerHTML = 'Off';
	}

	document.getElementById('cam-x').innerHTML = data.camX;
	document.getElementById('cam-y').innerHTML = data.camY;
	document.getElementById('cam-z').innerHTML = data.camZ;
	document.getElementById('cam-rot-x').innerHTML = data.camRotX;
	document.getElementById('cam-rot-y').innerHTML = data.camRotY;
	document.getElementById('cam-rot-z').innerHTML = data.camRotZ;
	document.getElementById('cursor-x').innerHTML = data.cursorX;
	document.getElementById('cursor-y').innerHTML = data.cursorY;
	document.getElementById('cursor-z').innerHTML = data.cursorZ;
	document.getElementById('interior-id').innerHTML = data.interiorId;

	if (data.speedMode == 1) {
		document.querySelector('#adjust-speed').innerHTML = `[${data.adjustSpeed.toFixed(3)}]`;
	} else {
		document.querySelector('#adjust-speed').innerHTML = data.adjustSpeed.toFixed(3);
	}

	if (data.speedMode == 2) {
		document.querySelector('#rotate-speed').innerHTML = `[${data.rotateSpeed.toFixed(1)}]`;
	} else {
		document.querySelector('#rotate-speed').innerHTML = data.rotateSpeed.toFixed(1);
	}

	document.querySelector('#model-name').innerHTML = data.modelName;

	switch(data.entityType) {
		case 1:
			document.querySelector('#entity-type').innerHTML = 'Ped';
			break;
		case 2:
			document.querySelector('#entity-type').innerHTML = 'Vehicle';
			break;
		case 3:
			document.querySelector('#entity-type').innerHTML = 'Object';
			break;
		default:
			document.querySelector('#entity-type').innerHTML = 'Entity';
			break;
	}

	var focusInfo = document.getElementById('focus-info');

	if (data.focusTarget) {
		document.getElementById('focus-target').innerHTML = data.focusTarget.toString();
		document.getElementById('focus-mode').innerHTML = data.freeFocus ? 'Free' : 'Fixed';
		focusInfo.style.display = 'block';
	} else {
		focusInfo.style.display = 'none';
	}
}

function openSpawnMenu() {
	switch (lastSpawnMenu) {
		case 0:
			document.querySelector('#ped-menu').style.display = 'flex';
			break;
		case 1:
			document.querySelector('#vehicle-menu').style.display = 'flex';
			break;
		case 2:
			document.querySelector('#object-menu').style.display = 'flex';
			break;
		case 3:
			document.querySelector('#propset-menu').style.display = 'flex';
			break;
		case 4:
			document.querySelector('#pickup-menu').style.display = 'flex';
			break;
		case 5:
			openSavedPedsMenu();
			break;
		case 6:
			openMpPedsMenu();
			break;
		case 7:
			document.querySelector('#particle-menu').style.display = 'flex';
			break;
		default:
			document.querySelector('#spawn-menu').style.display = 'flex';
			break;
	}
}

function closeSpawnMenu() {
	document.querySelector('#spawn-menu').style.display = 'none';
	sendMessage('closeSpawnMenu', {})
}

function openPedMenu() {
	document.querySelector('#spawn-menu').style.display = 'none';
	document.querySelector('#ped-menu').style.display = 'flex';
	lastSpawnMenu = 0;
}

function openVehicleMenu() {
	document.querySelector('#spawn-menu').style.display = 'none';
	document.querySelector('#vehicle-menu').style.display = 'flex';
	lastSpawnMenu = 1;
}

function openObjectMenu() {
	document.querySelector('#spawn-menu').style.display = 'none';
	document.querySelector('#object-menu').style.display = 'flex';
	lastSpawnMenu = 2;
}

function openPropsetMenu() {
	document.querySelector('#spawn-menu').style.display = 'none';
	document.querySelector('#propset-menu').style.display = 'flex';
	lastSpawnMenu = 3;
}

function openPickupMenu() {
	document.querySelector('#spawn-menu').style.display = 'none';
	document.querySelector('#pickup-menu').style.display = 'flex';
	lastSpawnMenu = 4;
}

function openParticleMenu() {
	document.querySelector('#spawn-menu').style.display = 'none';
	document.querySelector('#particle-menu').style.display = 'flex';
	lastSpawnMenu = 7;
}

