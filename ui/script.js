var isSpoonerHudOpened = false;
var peds = [];
var vehicles = [];
var objects = [];
var scenarios = [];
var weapons = [];
var animations = {};
var propsets = [];
var pickups = [];
var walkStyleBases = [];
var walkStyles = [];

var lastSpawnMenu = -1;

var searchDebounceTimer = null;

// ============================================================================
// Unified Spawn Menu System
// ============================================================================

var SpawnMenuConfig = {
	ped: {
		id: 'ped',
		dataSource: function() { return peds; },
		favouriteType: 'peds',
		closeMessage: 'closePedMenu',
		previewMessage: 'previewPed',
		spawnAttachMessage: 'spawnAndAttachPed',
		clearPreviewMessage: 'clearPedPreview',
		supportsPreview: true,
		supportsAttach: true
	},
	vehicle: {
		id: 'vehicle',
		dataSource: function() { return vehicles; },
		favouriteType: 'vehicles',
		closeMessage: 'closeVehicleMenu',
		previewMessage: 'previewVehicle',
		spawnAttachMessage: 'spawnAndAttachVehicle',
		clearPreviewMessage: 'clearVehiclePreview',
		supportsPreview: true,
		supportsAttach: true
	},
	object: {
		id: 'object',
		dataSource: function() { return objects; },
		favouriteType: 'objects',
		closeMessage: 'closeObjectMenu',
		previewMessage: 'previewObject',
		spawnAttachMessage: 'spawnAndAttachObject',
		clearPreviewMessage: 'clearObjectPreview',
		supportsPreview: true,
		supportsAttach: true
	},
	propset: {
		id: 'propset',
		dataSource: function() { return propsets; },
		favouriteType: 'propsets',
		closeMessage: 'closePropsetMenu',
		previewMessage: 'previewPropset',
		spawnAttachMessage: 'spawnAndAttachPropset',
		clearPreviewMessage: 'clearPropsetPreview',
		supportsPreview: false,  // Propsets use special API, preview not supported
		supportsAttach: true
	},
	pickup: {
		id: 'pickup',
		dataSource: function() { return pickups; },
		favouriteType: 'pickups',
		closeMessage: 'closePickupMenu',
		previewMessage: 'previewPickup',
		spawnAttachMessage: 'spawnAndAttachPickup',
		clearPreviewMessage: 'clearPickupPreview',
		supportsPreview: false,  // Pickups use special API
		supportsAttach: false  // Pickups don't attach
	}
};

var spawnMenuStates = {};

function initSpawnMenuState(configId) {
	spawnMenuStates[configId] = {
		pageSize: 100,
		currentPage: 0,
		filteredItems: [],
		selectedIndex: -1,
		searchDebounceTimer: null,
		previewDebounceTimer: null
	};
}

// Initialize states for all menus
Object.keys(SpawnMenuConfig).forEach(function(key) {
	initSpawnMenuState(key);
});

// Legacy alias for backward compatibility
var objectPagination = spawnMenuStates.object;

function getSpawnMenuElements(configId) {
	return {
		menu: document.getElementById(configId + '-menu'),
		searchFilter: document.getElementById(configId + '-search-filter'),
		favouriteBtn: document.getElementById('favourite-' + configId + 's'),
		list: document.getElementById(configId + '-list'),
		paginationControls: document.getElementById(configId + '-pagination-controls'),
		paginationInfo: document.getElementById(configId + '-pagination-info'),
		prevPageBtn: document.getElementById(configId + '-prev-page'),
		nextPageBtn: document.getElementById(configId + '-next-page'),
		spawnBtn: document.getElementById(configId + '-spawn-btn'),
		spawnByNameBtn: document.getElementById(configId + '-spawn-by-name'),
		closeBtn: document.getElementById(configId + '-menu-close-btn'),
		navHint: document.getElementById(configId + '-nav-hint')
	};
}

function filterSpawnMenuItems(configId, filter) {
	var config = SpawnMenuConfig[configId];
	var state = spawnMenuStates[configId];
	var elements = getSpawnMenuElements(configId);

	var favsOnly = elements.favouriteBtn && elements.favouriteBtn.hasAttribute('data-active');
	var filterLower = filter ? filter.toLowerCase() : '';
	var items = config.dataSource();

	state.filteredItems = [];

	for (var i = 0; i < items.length; i++) {
		var name = items[i];
		var isFav = favourites[config.favouriteType] && favourites[config.favouriteType][name];

		if (favsOnly && !isFav) {
			continue;
		}

		if (!filter || filter === '' || name.toLowerCase().includes(filterLower)) {
			state.filteredItems.push(name);
		}
	}

	state.currentPage = 0;
	state.selectedIndex = -1;
}

function renderSpawnMenuPage(configId) {
	var config = SpawnMenuConfig[configId];
	var state = spawnMenuStates[configId];
	var elements = getSpawnMenuElements(configId);

	var start = state.currentPage * state.pageSize;
	var end = Math.min(start + state.pageSize, state.filteredItems.length);

	elements.list.innerHTML = '';

	for (var i = start; i < end; i++) {
		var name = state.filteredItems[i];
		var isFav = favourites[config.favouriteType] && favourites[config.favouriteType][name];

		var div = document.createElement('div');

		if (state.selectedIndex === i) {
			div.className = 'object selected';
		} else if (isFav) {
			div.className = 'object favourite';
		} else {
			div.className = 'object';
		}

		div.setAttribute('data-model', name);
		div.setAttribute('data-favourite-type', config.favouriteType);
		div.setAttribute('data-favourite-name', name);
		div.setAttribute('data-index', i);
		div.setAttribute('data-menu-id', configId);

		div.innerHTML = name;
		div.title = name;

		// Click selects for preview
		div.addEventListener('click', function(event) {
			var index = parseInt(this.getAttribute('data-index'));
			var menuId = this.getAttribute('data-menu-id');
			selectSpawnMenuItem(menuId, index);
		});

		if (isFav) {
			div.addEventListener('contextmenu', favouriteOnClick);
		} else {
			div.addEventListener('contextmenu', nonFavouriteOnClick);
		}

		elements.list.appendChild(div);
	}

	updateSpawnMenuPaginationInfo(configId);
	updateSpawnMenuButtonState(configId);
}

function updateSpawnMenuButtonState(configId) {
	var state = spawnMenuStates[configId];
	var elements = getSpawnMenuElements(configId);

	if (elements.spawnBtn) {
		elements.spawnBtn.disabled = state.selectedIndex < 0;
	}
}

function updateSpawnMenuPaginationInfo(configId) {
	var state = spawnMenuStates[configId];
	var elements = getSpawnMenuElements(configId);

	if (!elements.paginationInfo) return;

	var total = state.filteredItems.length;
	var start = state.currentPage * state.pageSize + 1;
	var end = Math.min(start + state.pageSize - 1, total);
	var totalPages = Math.ceil(total / state.pageSize);
	var currentPage = state.currentPage + 1;

	if (total === 0) {
		elements.paginationInfo.innerHTML = 'No results';
	} else {
		elements.paginationInfo.innerHTML = start + '-' + end + ' of ' + total + ' (Page ' + currentPage + '/' + totalPages + ')';
	}

	if (elements.prevPageBtn) {
		elements.prevPageBtn.disabled = state.currentPage === 0;
	}
	if (elements.nextPageBtn) {
		elements.nextPageBtn.disabled = end >= total;
	}
}

function spawnMenuPrevPage(configId) {
	var state = spawnMenuStates[configId];
	if (state.currentPage > 0) {
		state.currentPage--;
		state.selectedIndex = -1;
		renderSpawnMenuPage(configId);
	}
}

function spawnMenuNextPage(configId) {
	var state = spawnMenuStates[configId];
	var totalPages = Math.ceil(state.filteredItems.length / state.pageSize);
	if (state.currentPage < totalPages - 1) {
		state.currentPage++;
		state.selectedIndex = -1;
		renderSpawnMenuPage(configId);
	}
}

function selectSpawnMenuItem(configId, index) {
	var config = SpawnMenuConfig[configId];
	var state = spawnMenuStates[configId];
	var elements = getSpawnMenuElements(configId);

	if (index < 0 || index >= state.filteredItems.length) {
		return;
	}

	state.selectedIndex = index;

	// Calculate which page this index is on
	var targetPage = Math.floor(index / state.pageSize);
	if (targetPage !== state.currentPage) {
		state.currentPage = targetPage;
	}

	renderSpawnMenuPage(configId);

	// Scroll the selected item into view
	var selectedEl = elements.list.querySelector('.object.selected');
	if (selectedEl) {
		selectedEl.scrollIntoView({ block: 'nearest' });
	}

	// Show preview with debounce
	if (config.supportsPreview) {
		if (state.previewDebounceTimer) {
			clearTimeout(state.previewDebounceTimer);
		}
		state.previewDebounceTimer = setTimeout(function() {
			var modelName = state.filteredItems[index];
			sendMessage(config.previewMessage, { modelName: modelName });
		}, 150);
	}
}

function spawnMenuNavigate(configId, direction) {
	var state = spawnMenuStates[configId];
	var newIndex = state.selectedIndex + direction;

	if (newIndex < 0) {
		newIndex = 0;
	} else if (newIndex >= state.filteredItems.length) {
		newIndex = state.filteredItems.length - 1;
	}

	if (newIndex !== state.selectedIndex) {
		selectSpawnMenuItem(configId, newIndex);
	}
}

function spawnSelectedItem(configId) {
	var config = SpawnMenuConfig[configId];
	var state = spawnMenuStates[configId];
	var elements = getSpawnMenuElements(configId);

	if (state.selectedIndex < 0) {
		return;
	}

	var modelName = state.filteredItems[state.selectedIndex];
	if (modelName) {
		elements.menu.style.display = 'none';

		if (config.supportsAttach) {
			// Spawn and attach to camera immediately
			sendMessage(config.spawnAttachMessage, { modelName: modelName });
		} else {
			// Just spawn (for pickups, etc.)
			sendMessage(config.closeMessage, { modelName: modelName });
		}

		// Reset selection state
		state.selectedIndex = -1;
		updateSpawnMenuButtonState(configId);
	}
}

function spawnByNameOrHash(configId) {
	var config = SpawnMenuConfig[configId];
	var elements = getSpawnMenuElements(configId);
	var name = elements.searchFilter ? elements.searchFilter.value.trim() : '';

	if (!name) {
		return;
	}

	elements.menu.style.display = 'none';

	if (config.supportsAttach) {
		sendMessage(config.spawnAttachMessage, { modelName: name });
	} else {
		sendMessage(config.closeMessage, { modelName: name });
	}

	// Clear preview
	if (config.supportsPreview) {
		sendMessage(config.clearPreviewMessage, {});
	}
}

function closeEntitySpawnMenu(configId) {
	var config = SpawnMenuConfig[configId];
	var state = spawnMenuStates[configId];
	var elements = getSpawnMenuElements(configId);

	elements.menu.style.display = 'none';

	// Clear preview when closing menu without spawning
	if (config.supportsPreview) {
		sendMessage(config.clearPreviewMessage, {});
	}
	// Show spawn menu again (Back button behavior)
	document.querySelector('#spawn-menu').style.display = 'flex';
	lastSpawnMenu = -1;

	// Reset selection state
	state.selectedIndex = -1;
	updateSpawnMenuButtonState(configId);
}

function populateSpawnMenu(configId, filter, immediate) {
	var state = spawnMenuStates[configId];

	if (state.searchDebounceTimer) {
		clearTimeout(state.searchDebounceTimer);
	}

	if (immediate) {
		filterSpawnMenuItems(configId, filter);
		renderSpawnMenuPage(configId);
	} else {
		state.searchDebounceTimer = setTimeout(function() {
			filterSpawnMenuItems(configId, filter);
			renderSpawnMenuPage(configId);
		}, 150);
	}
}

function setupSpawnMenuEventListeners(configId) {
	var config = SpawnMenuConfig[configId];
	var elements = getSpawnMenuElements(configId);

	// Search filter
	if (elements.searchFilter) {
		elements.searchFilter.addEventListener('input', function(event) {
			populateSpawnMenu(configId, this.value);
		});
	}

	// Pagination controls
	if (elements.prevPageBtn) {
		elements.prevPageBtn.addEventListener('click', function(event) {
			spawnMenuPrevPage(configId);
		});
	}

	if (elements.nextPageBtn) {
		elements.nextPageBtn.addEventListener('click', function(event) {
			spawnMenuNextPage(configId);
		});
	}

	// Spawn button
	if (elements.spawnBtn) {
		elements.spawnBtn.addEventListener('click', function(event) {
			spawnSelectedItem(configId);
		});
	}

	// Spawn By Name/Hash button
	if (elements.spawnByNameBtn) {
		elements.spawnByNameBtn.addEventListener('click', function(event) {
			spawnByNameOrHash(configId);
		});
	}

	// Close button (Back)
	if (elements.closeBtn) {
		elements.closeBtn.addEventListener('click', function() {
			closeEntitySpawnMenu(configId);
		});
	}
}

function setupSpawnMenuKeyboardNav(configId) {
	var config = SpawnMenuConfig[configId];
	var elements = getSpawnMenuElements(configId);
	var state = spawnMenuStates[configId];

	document.addEventListener('keydown', function(event) {
		if (!elements.menu || elements.menu.style.display !== 'flex') return;

		var isSearchFocused = document.activeElement === elements.searchFilter;

		switch(event.key) {
			case 'ArrowUp':
				if (!isSearchFocused) {
					event.preventDefault();
					spawnMenuNavigate(configId, -1);
				}
				break;
			case 'ArrowDown':
				if (!isSearchFocused) {
					event.preventDefault();
					spawnMenuNavigate(configId, 1);
				}
				break;
			case 'PageUp':
				event.preventDefault();
				spawnMenuPrevPage(configId);
				if (state.filteredItems.length > 0) {
					selectSpawnMenuItem(configId, state.currentPage * state.pageSize);
				}
				break;
			case 'PageDown':
				event.preventDefault();
				spawnMenuNextPage(configId);
				if (state.filteredItems.length > 0) {
					selectSpawnMenuItem(configId, state.currentPage * state.pageSize);
				}
				break;
			case 'Enter':
				if (!isSearchFocused && state.selectedIndex >= 0) {
					event.preventDefault();
					spawnSelectedItem(configId);
				}
				break;
			case 'Escape':
				event.preventDefault();
				closeEntitySpawnMenu(configId);
				break;
		}
	});
}

// Initialize all spawn menu event listeners
function initAllSpawnMenus() {
	Object.keys(SpawnMenuConfig).forEach(function(configId) {
		setupSpawnMenuEventListeners(configId);
		setupSpawnMenuKeyboardNav(configId);
	});
}

// ============================================================================
// End Unified Spawn Menu System
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

function openSavedPedsMenu() {
	document.querySelector('#spawn-menu').style.display = 'none';
	document.querySelector('#saved-peds-menu').style.display = 'flex';
	lastSpawnMenu = 5;

	sendMessage('getSavedPeds', {}).then(resp => resp.json()).then(resp => updateSavedPedsList(resp));
}

function closeSavedPedsMenu(spawned) {
	document.querySelector('#saved-peds-menu').style.display = 'none';

	if (!spawned) {
		document.querySelector('#spawn-menu').style.display = 'flex';
		lastSpawnMenu = -1;
	}
}

function updateSavedPedsList(data) {
	var names = JSON.parse(data);
	var list = document.querySelector('#saved-peds-list');

	list.innerHTML = '';

	if (!names.length) {
		var empty = document.createElement('div');
		empty.className = 'saved-ped-empty';
		empty.innerHTML = 'No saved peds yet';
		list.appendChild(empty);
		return;
	}

	names.forEach(function(name) {
		list.appendChild(createSavedPedRow(name));
	});
}

function createSavedPedRow(name) {
	var row = document.createElement('div');
	row.className = 'saved-ped';
	row.setAttribute('data-name', name);

	var label = document.createElement('span');
	label.className = 'saved-ped-name';
	label.title = 'Spawn';
	label.innerHTML = name;
	label.addEventListener('click', function(event) {
		sendMessage('spawnSavedPed', {
			name: row.getAttribute('data-name')
		});
		closeSavedPedsMenu(true);
	});

	var renameBtn = document.createElement('button');
	renameBtn.className = 'saved-ped-action';
	renameBtn.title = 'Rename';
	renameBtn.innerHTML = '<i class="fas fa-pen"></i>';
	renameBtn.addEventListener('click', function(event) {
		event.stopPropagation();
		startRenameSavedPed(row);
	});

	var deleteBtn = document.createElement('button');
	deleteBtn.className = 'saved-ped-action saved-ped-delete';
	deleteBtn.title = 'Delete';
	deleteBtn.innerHTML = '<i class="fas fa-trash"></i>';
	deleteBtn.addEventListener('click', function(event) {
		event.stopPropagation();

		sendMessage('deleteSavedPed', {
			name: row.getAttribute('data-name')
		});
		row.remove();

		if (!document.querySelector('#saved-peds-list .saved-ped')) {
			updateSavedPedsList('[]');
		}
	});

	row.appendChild(label);
	row.appendChild(renameBtn);
	row.appendChild(deleteBtn);

	return row;
}

function startRenameSavedPed(row) {
	var oldName = row.getAttribute('data-name');

	row.innerHTML = '';

	var input = document.createElement('input');
	input.type = 'text';
	input.className = 'saved-ped-rename-input';
	input.value = oldName;

	var confirmBtn = document.createElement('button');
	confirmBtn.className = 'saved-ped-action';
	confirmBtn.title = 'Confirm';
	confirmBtn.innerHTML = '<i class="fas fa-check"></i>';

	var cancelBtn = document.createElement('button');
	cancelBtn.className = 'saved-ped-action saved-ped-delete';
	cancelBtn.title = 'Cancel';
	cancelBtn.innerHTML = '<i class="fas fa-times"></i>';

	function commit() {
		var newName = input.value.trim();

		if (!newName || newName === oldName) {
			cancel();
			return;
		}

		sendMessage('renameSavedPed', {
			oldName: oldName,
			newName: newName
		}).then(resp => resp.json()).then(resp => updateSavedPedsList(resp));
	}

	function cancel() {
		row.replaceWith(createSavedPedRow(oldName));
	}

	confirmBtn.addEventListener('click', function(event) {
		event.stopPropagation();
		commit();
	});

	cancelBtn.addEventListener('click', function(event) {
		event.stopPropagation();
		cancel();
	});

	input.addEventListener('keydown', function(event) {
		if (event.key === 'Enter') {
			commit();
		} else if (event.key === 'Escape') {
			event.stopPropagation();
			cancel();
		}
	});

	row.appendChild(input);
	row.appendChild(confirmBtn);
	row.appendChild(cancelBtn);

	input.focus();
	input.select();
}

function closePedMenu(selected) {
	document.querySelector('#ped-menu').style.display = 'none';

	if (selected) {
		var name = selected.getAttribute('data-model');

		sendMessage('closePedMenu', {
			modelName: name
		});

		document.querySelectorAll('#ped-list .object').forEach(e => {
			if (favourites.peds[e.getAttribute('data-model')]) {
				e.className = 'object favourite';
			} else {
				e.className = 'object';
			}
		});
		selected.className = 'object selected';
	} else {
		document.querySelector('#spawn-menu').style.display = 'flex';
		lastSpawnMenu = -1;
	}
}

function closeVehicleMenu(selected) {
	document.querySelector('#vehicle-menu').style.display = 'none';

	if (selected) {
		var name = selected.getAttribute('data-model');

		sendMessage('closeVehicleMenu', {
			modelName: name
		});

		document.querySelectorAll('#vehicle-list .object').forEach(e => {
			if (favourites.vehicles[e.getAttribute('data-model')]) {
				e.className = 'object favourite';
			} else {
				e.className = 'object';
			}
		});
		selected.className = 'object selected';
	} else {
		document.querySelector('#spawn-menu').style.display = 'flex';
		lastSpawnMenu = -1;
	}
}

function closeObjectMenu(selected) {
	document.querySelector('#object-menu').style.display = 'none';

	if (selected) {
		var name = selected.getAttribute('data-model');

		sendMessage('closeObjectMenu', {
			modelName: name
		});

		document.querySelectorAll('#object-list .object').forEach(e => {
			if (favourites.objects[e.getAttribute('data-model')]) {
				e.className = 'object favourite';
			} else {
				e.className = 'object';
			}
		});
		selected.className = 'object selected';
	} else {
		// Clear preview when closing menu without spawning
		sendMessage('clearObjectPreview', {});
		document.querySelector('#spawn-menu').style.display = 'flex';
		lastSpawnMenu = -1;
	}

	// Reset selection state
	objectPagination.selectedIndex = -1;
	updateSpawnButtonState();
}

function closePropsetMenu(selected) {
	document.querySelector('#propset-menu').style.display = 'none';

	if (selected) {
		var name = selected.getAttribute('data-model');

		sendMessage('closePropsetMenu', {
			modelName: name
		});

		document.querySelectorAll('#propset-list .object').forEach(e => {
			if (favourites.propsets[e.getAttribute('data-model')]) {
				e.className = 'object favourite';
			} else {
				e.className = 'object';
			}
		});
		selected.className = 'object selected';
	} else {
		document.querySelector('#spawn-menu').style.display = 'flex';
		lastSpawnMenu = -1;
	}
}

function closePickupMenu(selected) {
	document.querySelector('#pickup-menu').style.display = 'none';

	if (selected) {
		var name = selected.getAttribute('data-model');

		sendMessage('closePickupMenu', {
			modelName: name
		});

		document.querySelectorAll('#pickup-list .object').forEach(e => {
			if (favourites.pickups[e.getAttribute('data-model')]) {
				e.className = 'object favourite';
			} else {
				e.className = 'object';
			}
		});
		selected.className = 'object selected';
	} else {
		document.querySelector('#spawn-menu').style.display = 'flex';
		lastSpawnMenu = -1;
	}
}

function performScenario(scenario) {
	document.querySelectorAll('#scenario-list .object').forEach(e => {
		if (favourites.scenarios[e.getAttribute('data-scenario')]) {
			e.className = 'object favourite';
		} else {
			e.className = 'object';
		}
	});
	scenario.className = 'object selected';

	sendMessage('performScenario', {
		handle: currentEntity(),
		scenario: scenario.getAttribute('data-scenario')
	});
}

function giveWeapon(weapon) {
	sendMessage('giveWeapon', {
		handle: currentEntity(),
		weapon: weapon.getAttribute('data-model')
	});
}

// Shorten an animation's dict to its last 3 segments + the action name,
// e.g. "ai_combat@...@holstered@base@1h" + "back_left_-135" -> "holstered@base@1h: back_left_-135"
function shortAnimLabel(dict, name) {
	var shortDict = dict.split('@').slice(-3).join('@');
	return shortDict + ': ' + name;
}

function playAnimation(animation) {
	document.querySelectorAll('#animation-list .object').forEach(e => {
		if (favourites.animations[e.getAttribute('data-dict') + ': ' + e.getAttribute('data-name')]) {
			e.className = 'object favourite';
		} else {
			e.className = 'object';
		}
	});
	animation.className = 'object selected';

	document.getElementById('animation-selected-name').innerHTML =
		animation.getAttribute('data-dict') + ': ' + animation.getAttribute('data-name');

	sendMessage('playAnimation', {
		handle: currentEntity(),
		dict: animation.getAttribute('data-dict'),
		name: animation.getAttribute('data-name'),
		blendInSpeed: parseFloat(document.querySelector('#animation-blend-in-speed').value),
		blendOutSpeed: parseFloat(document.querySelector('#animation-blend-out-speed').value),
		duration: parseInt(document.querySelector('#animation-duration').value),
		flag: parseInt(document.querySelector('#animation-flag').value),
		playbackRate: parseFloat(document.querySelector('#animation-playback-rate').value)
	});

	startAnimTimeline();
}

// Animation Timeline
var animTimelineInterval = null;

function startAnimTimeline() {
	var timeline = document.getElementById('animation-timeline');
	timeline.style.display = 'block';

	if (animTimelineInterval) clearInterval(animTimelineInterval);
	animTimelineInterval = setInterval(function() {
		sendMessage('getAnimationTime', {
			handle: currentEntity()
		}).then(r => r.json()).then(function(data) {
			if (!data.hasAnimation) {
				document.getElementById('animation-timeline').style.display = 'none';
				return;
			}
			var slider = document.getElementById('animation-time-slider');
			if (!slider.matches(':active')) {
				slider.value = data.time;
			}
			document.getElementById('animation-time-display').innerText =
				(data.time * 100).toFixed(1) + '%';

			document.getElementById('animation-pause').style.display = data.isPaused ? 'none' : 'inline-block';
			document.getElementById('animation-resume').style.display = data.isPaused ? 'inline-block' : 'none';
		});
	}, 100);
}

function stopAnimTimeline() {
	if (animTimelineInterval) {
		clearInterval(animTimelineInterval);
		animTimelineInterval = null;
	}
	document.getElementById('animation-timeline').style.display = 'none';
}

// Entity Offset
var offsetReferenceEntity = null;
var offsetInterval = null;

function startOffsetPolling(entity, reference) {
	offsetReferenceEntity = reference;
	document.getElementById('offset-display').style.display = 'block';
	document.getElementById('offset-reference-id').innerText = reference;

	if (offsetInterval) clearInterval(offsetInterval);
	offsetInterval = setInterval(function() {
		sendMessage('getEntityOffset', {
			handle: currentEntity(),
			reference: offsetReferenceEntity
		}).then(r => r.json()).then(function(data) {
			if (data.error) { clearOffsetReference(); return; }
			document.getElementById('offset-local-x').value = data.localX;
			document.getElementById('offset-local-y').value = data.localY;
			document.getElementById('offset-local-z').value = data.localZ;
			document.getElementById('offset-pitch').value = data.dPitch;
			document.getElementById('offset-roll').value = data.dRoll;
			document.getElementById('offset-yaw').value = data.dYaw;
			document.getElementById('offset-distance').innerText = data.distance;
		});
	}, 500);
}

function clearOffsetReference() {
	offsetReferenceEntity = null;
	if (offsetInterval) clearInterval(offsetInterval);
	offsetInterval = null;
	document.getElementById('offset-display').style.display = 'none';
}

function setWalkStyle(selected) {
	sendMessage('setWalkStyle', {
		handle: currentEntity(),
		base: selected.getAttribute('data-base'),
		style: selected.getAttribute('data-style')
	});

	document.querySelectorAll('#walk-style-list .object').forEach(e => {
		if (favourites.walkStyles[e.getAttribute('data-base') + ': ' + e.getAttribute('data-style')]) {
			e.className = 'object favourite';
		} else {
			e.className = 'object';
		}
	});
	selected.className = 'object selected';
}

function favouriteOnClick(event) {
	removeFavourite(this);
}

function nonFavouriteOnClick(event) {
	addFavourite(this);
}

function addFavourite(selected) {
	var type = selected.getAttribute('data-favourite-type');
	var name = selected.getAttribute('data-favourite-name');

	favourites[type][name] = true;

	sendMessage('saveFavourites', {
		favourites: favourites
	});

	selected.className = 'object favourite';
	selected.removeEventListener('contextmenu', nonFavouriteOnClick);
	selected.addEventListener('contextmenu', favouriteOnClick);
}

function removeFavourite(selected) {
	var type = selected.getAttribute('data-favourite-type');
	var name = selected.getAttribute('data-favourite-name');

	delete favourites[type][name];

	sendMessage('saveFavourites', {
		favourites: favourites
	});

	selected.className = 'object';
	selected.removeEventListener('contextmenu', favouriteOnClick);
	selected.addEventListener('contextmenu', nonFavouriteOnClick);
}

function populatePedList(filter) {
	var pedList = document.getElementById('ped-list');
	var favsOnly = document.getElementById('favourite-peds').hasAttribute('data-active');

	pedList.innerHTML = '';

	peds.forEach(name => {
		var isFav = favourites.peds[name];

		if (favsOnly && !isFav) {
			return;
		}

		if (!filter || filter == '' || name.toLowerCase().includes(filter.toLowerCase())) {
			var div = document.createElement('div');

			if (isFav) {
				div.className = 'object favourite';
			} else {
				div.className = 'object';
			}

			div.setAttribute('data-model', name);
			div.setAttribute('data-favourite-type', 'peds');
			div.setAttribute('data-favourite-name', name);

			div.innerHTML = name;
			div.title = name;

			div.addEventListener('click', function(event) {
				closePedMenu(this);
			});

			if (isFav) {
				div.addEventListener('contextmenu', favouriteOnClick);
			} else {
				div.addEventListener('contextmenu', nonFavouriteOnClick);
			}

			pedList.appendChild(div);
		}
	});
}

function setPlayerModel(modelName) {
	sendMessage('setPlayerModel', {
		modelName: modelName
	}).then(resp => resp.json()).then(resp => {
		document.getElementById('properties-menu-entity-id').setAttribute('data-handle', resp.handle);
		clearInterval(propertiesMenuUpdate);
		propertiesMenuUpdate = setInterval(function() {
			sendUpdatePropertiesMenuMessage(resp.handle, false);
		}, 500);
	});
}

function populatePlayerModelList(filter) {
	var pedList = document.getElementById('player-model-list');
	var favsOnly = document.getElementById('favourite-player-models').hasAttribute('data-active');

	pedList.innerHTML = '';

	peds.forEach(name => {
		var isFav = favourites.playerModels[name];

		if (favsOnly && !isFav) {
			return;
		}

		if (!filter || filter == '' || name.toLowerCase().includes(filter.toLowerCase())) {
			var div = document.createElement('div');

			if (isFav) {
				div.className = 'object favourite';
			} else {
				div.className = 'object';
			}

			div.setAttribute('data-model', name);
			div.setAttribute('data-favourite-type', 'playerModels');
			div.setAttribute('data-favourite-name', name);

			div.innerHTML = name;
			div.title = name;

			div.addEventListener('click', function(event) {
				pedList.querySelectorAll('.object').forEach(e => {
					if (favourites.playerModels[e.getAttribute('data-model')]) {
						e.className = 'object favourite';
					} else {
						e.className = 'object';
					}
				});
				this.className = 'object selected';
				setPlayerModel(this.getAttribute('data-model'));
			});

			if (isFav) {
				div.addEventListener('contextmenu', favouriteOnClick);
			} else {
				div.addEventListener('contextmenu', nonFavouriteOnClick);
			}

			pedList.appendChild(div);
		}
	});
}

function populateVehicleList(filter) {
	var vehicleList = document.getElementById('vehicle-list');
	var favsOnly = document.getElementById('favourite-vehicles').hasAttribute('data-active');

	vehicleList.innerHTML = '';

	vehicles.forEach(name => {
		var isFav = favourites.vehicles[name];

		if (favsOnly && !isFav) {
			return;
		}

		if (!filter || filter == '' || name.toLowerCase().includes(filter.toLowerCase())) {
			var div = document.createElement('div');

			if (isFav) {
				div.className = 'object favourite';
			} else {
				div.className = 'object';
			}

			div.setAttribute('data-model', name);
			div.setAttribute('data-favourite-type', 'vehicles');
			div.setAttribute('data-favourite-name', name);

			div.innerHTML = name;
			div.title = name;

			div.addEventListener('click', function(event) {
				closeVehicleMenu(this);
			});

			if (isFav) {
				div.addEventListener('contextmenu', favouriteOnClick);
			} else {
				div.addEventListener('contextmenu', nonFavouriteOnClick);
			}

			vehicleList.appendChild(div);
		}
	});
}

function filterObjects(filter) {
	var favsOnly = document.getElementById('favourite-objects').hasAttribute('data-active');
	var filterLower = filter ? filter.toLowerCase() : '';

	objectPagination.filteredObjects = [];

	for (var i = 0; i < objects.length; i++) {
		var name = objects[i];
		var isFav = favourites.objects[name];

		if (favsOnly && !isFav) {
			continue;
		}

		if (!filter || filter === '' || name.toLowerCase().includes(filterLower)) {
			objectPagination.filteredObjects.push(name);
		}
	}

	objectPagination.currentPage = 0;
	objectPagination.selectedIndex = -1;
}

function renderObjectPage() {
	var objectList = document.getElementById('object-list');
	var start = objectPagination.currentPage * objectPagination.pageSize;
	var end = Math.min(start + objectPagination.pageSize, objectPagination.filteredObjects.length);

	objectList.innerHTML = '';

	for (var i = start; i < end; i++) {
		var name = objectPagination.filteredObjects[i];
		var isFav = favourites.objects[name];

		var div = document.createElement('div');

		if (objectPagination.selectedIndex === i) {
			div.className = 'object selected';
		} else if (isFav) {
			div.className = 'object favourite';
		} else {
			div.className = 'object';
		}

		div.setAttribute('data-model', name);
		div.setAttribute('data-favourite-type', 'objects');
		div.setAttribute('data-favourite-name', name);
		div.setAttribute('data-index', i);

		div.innerHTML = name;
		div.title = name;

		// Click selects for preview, doesn't close menu
		div.addEventListener('click', function(event) {
			var index = parseInt(this.getAttribute('data-index'));
			selectObjectByIndex(index);
		});

		if (isFav) {
			div.addEventListener('contextmenu', favouriteOnClick);
		} else {
			div.addEventListener('contextmenu', nonFavouriteOnClick);
		}

		objectList.appendChild(div);
	}

	updateObjectPaginationInfo();
	updateSpawnButtonState();
}

function updateSpawnButtonState() {
	var spawnBtn = document.getElementById('object-spawn-btn');
	if (objectPagination.selectedIndex >= 0) {
		spawnBtn.disabled = false;
	} else {
		spawnBtn.disabled = true;
	}
}

function updateObjectPaginationInfo() {
	var infoEl = document.getElementById('object-pagination-info');
	var total = objectPagination.filteredObjects.length;
	var start = objectPagination.currentPage * objectPagination.pageSize + 1;
	var end = Math.min(start + objectPagination.pageSize - 1, total);
	var totalPages = Math.ceil(total / objectPagination.pageSize);
	var currentPage = objectPagination.currentPage + 1;

	if (total === 0) {
		infoEl.innerHTML = 'No results';
	} else {
		infoEl.innerHTML = start + '-' + end + ' of ' + total + ' (Page ' + currentPage + '/' + totalPages + ')';
	}

	document.getElementById('object-prev-page').disabled = objectPagination.currentPage === 0;
	document.getElementById('object-next-page').disabled = end >= total;
}

function objectPrevPage() {
	if (objectPagination.currentPage > 0) {
		objectPagination.currentPage--;
		objectPagination.selectedIndex = -1; // Reset selection on page change
		renderObjectPage();
	}
}

function objectNextPage() {
	var totalPages = Math.ceil(objectPagination.filteredObjects.length / objectPagination.pageSize);
	if (objectPagination.currentPage < totalPages - 1) {
		objectPagination.currentPage++;
		objectPagination.selectedIndex = -1; // Reset selection on page change
		renderObjectPage();
	}
}

var previewDebounceTimer = null;

function selectObjectByIndex(index) {
	if (index < 0 || index >= objectPagination.filteredObjects.length) {
		return;
	}

	objectPagination.selectedIndex = index;

	// Calculate which page this index is on
	var targetPage = Math.floor(index / objectPagination.pageSize);
	if (targetPage !== objectPagination.currentPage) {
		objectPagination.currentPage = targetPage;
	}

	renderObjectPage();

	// Scroll the selected item into view
	var objectList = document.getElementById('object-list');
	var selectedEl = objectList.querySelector('.object.selected');
	if (selectedEl) {
		selectedEl.scrollIntoView({ block: 'nearest' });
	}

	// Show preview (with debounce to avoid lag when navigating fast)
	if (previewDebounceTimer) {
		clearTimeout(previewDebounceTimer);
	}
	previewDebounceTimer = setTimeout(function() {
		var modelName = objectPagination.filteredObjects[index];
		sendMessage('previewObject', { modelName: modelName });
	}, 150);
}

function objectNavigate(direction) {
	var newIndex = objectPagination.selectedIndex + direction;

	if (newIndex < 0) {
		newIndex = 0;
	} else if (newIndex >= objectPagination.filteredObjects.length) {
		newIndex = objectPagination.filteredObjects.length - 1;
	}

	if (newIndex !== objectPagination.selectedIndex) {
		selectObjectByIndex(newIndex);
	}
}

function spawnSelectedObject() {
	if (objectPagination.selectedIndex < 0) {
		return;
	}
	var modelName = objectPagination.filteredObjects[objectPagination.selectedIndex];
	if (modelName) {
		document.querySelector('#object-menu').style.display = 'none';
		// Spawn and attach to camera immediately
		sendMessage('spawnAndAttachObject', {
			modelName: modelName
		});
		// Reset selection state
		objectPagination.selectedIndex = -1;
		updateSpawnButtonState();
	}
}

function populateObjectList(filter, immediate) {
	// Use debounce for search to prevent lag (unless immediate is true)
	if (searchDebounceTimer) {
		clearTimeout(searchDebounceTimer);
	}

	if (immediate) {
		filterObjects(filter);
		renderObjectPage();
	} else {
		searchDebounceTimer = setTimeout(function() {
			filterObjects(filter);
			renderObjectPage();
		}, 150);
	}
}

function populateScenarioList(filter) {
	var scenarioList = document.getElementById('scenario-list');
	var favsOnly = document.getElementById('favourite-scenarios').hasAttribute('data-active');

	scenarioList.innerHTML = '';

	scenarios.forEach(scenario => {
		var isFav = favourites.scenarios[scenario];

		if (favsOnly && !isFav) {
			return;
		}

		if (!filter || filter == '' || scenario.toLowerCase().includes(filter.toLowerCase())) {
			var div = document.createElement('div');

			if (isFav) {
				div.className = 'object favourite';
			} else {
				div.className = 'object';
			}

			div.setAttribute('data-scenario', scenario);
			div.setAttribute('data-favourite-type', 'scenarios');
			div.setAttribute('data-favourite-name', scenario);

			div.innerHTML = scenario;

			div.addEventListener('click', function(event) {
				performScenario(this);
			});

			if (isFav) {
				div.addEventListener('contextmenu', favouriteOnClick);
			} else {
				div.addEventListener('contextmenu', nonFavouriteOnClick);
			}

			scenarioList.appendChild(div);
		}
	});
}

function populateWeaponList(filter) {
	var weaponList = document.getElementById('weapon-list');
	var favsOnly = document.getElementById('favourite-weapons').hasAttribute('data-active');

	weaponList.innerHTML = '';

	weapons.forEach(weapon => {
		var isFav = favourites.weapons[weapon];

		if (favsOnly && !isFav) {
			return;
		}

		if (!filter || filter == '' || weapon.toLowerCase().includes(filter.toLowerCase())) {
			var div = document.createElement('div');

			if (isFav) {
				div.className = 'object favourite';
			} else {
				div.className = 'object';
			}

			div.setAttribute('data-model', weapon);
			div.setAttribute('data-favourite-type', 'weapons');
			div.setAttribute('data-favourite-name', weapon);

			div.innerHTML = weapon;

			div.addEventListener('click', function(event) {
				giveWeapon(this);
			});

			if (isFav) {
				div.addEventListener('contextmenu', favouriteOnClick);
			} else {
				div.addEventListener('contextmenu', nonFavouriteOnClick);
			}

			weaponList.appendChild(div);
		}
	});
}

function populateAnimationList(filter) {
	var animationList = document.getElementById('animation-list');
	var animationMaxResults = parseInt(document.getElementById('animation-search-max-results').value);
	var favsOnly = document.getElementById('favourite-animations').hasAttribute('data-active');

	animationList.innerHTML = '';

	var results = [];

	Object.keys(animations).forEach(dict => {
		animations[dict].forEach(name => {
			var label = dict + ': ' + name;

			if (favsOnly && !favourites.animations[label]) {
				return;
			}

			if (!filter || filter == '' || label.toLowerCase().includes(filter.toLowerCase())) {
				results.push({
					label: label,
					dict: dict,
					name: name
				})
			}
		});
	});

	results.sort(function(a, b) {
		if (a.label < b.label) {
			return -1;
		}
		if (a.label > b.label) {
			return 1;
		}
		return 0;
	});

	document.getElementById('animation-search-total-results').innerHTML = results.length;

	for (var i = 0; i < results.length && i < animationMaxResults; ++i) {
		var isFav = favourites.animations[results[i].label];

		var div = document.createElement('div');

		if (isFav) {
			div.className = 'object favourite';
		} else {
			div.className = 'object';
		}

		div.setAttribute('data-dict', results[i].dict);
		div.setAttribute('data-name', results[i].name);
		div.setAttribute('data-favourite-type', 'animations');
		div.setAttribute('data-favourite-name', results[i].label);

		div.innerHTML = shortAnimLabel(results[i].dict, results[i].name);
		div.title = results[i].label;

		div.addEventListener('click', function() {
			playAnimation(this);
		});

		if (isFav) {
			div.addEventListener('contextmenu', favouriteOnClick);
		} else {
			div.addEventListener('contextmenu', nonFavouriteOnClick);
		}

		animationList.appendChild(div);
	}
}

function populatePropsetList(filter) {
	var propsetList = document.getElementById('propset-list');
	var favsOnly = document.getElementById('favourite-propsets').hasAttribute('data-active');

	propsetList.innerHTML = '';

	propsets.forEach(propset => {
		var isFav = favourites.propsets[propset];

		if (favsOnly && !isFav) {
			return;
		}

		if (!filter || filter == '' || propset.toLowerCase().includes(filter.toLowerCase())) {
			var div = document.createElement('div');

			if (isFav) {
				div.className = 'object favourite';
			} else {
				div.className = 'object';
			}

			div.setAttribute('data-model', propset);
			div.setAttribute('data-favourite-type', 'propsets');
			div.setAttribute('data-favourite-name', propset);

			div.innerHTML = propset;

			div.addEventListener('click', function(event) {
				closePropsetMenu(this);
			});

			if (isFav) {
				div.addEventListener('contextmenu', favouriteOnClick);
			} else {
				div.addEventListener('contextmenu', nonFavouriteOnClick);
			}

			propsetList.appendChild(div);
		}
	});
}

function populatePickupList(filter) {
	var pickupList = document.getElementById('pickup-list');
	var favsOnly = document.getElementById('favourite-pickups').hasAttribute('data-active');

	pickupList.innerHTML = '';

	pickups.forEach(pickup => {
		var isFav = favourites.pickups[pickup];

		if (favsOnly && !isFav) {
			return;
		}

		if (!filter || filter == '' || pickup.toLowerCase().includes(filter.toLowerCase())) {
			var div = document.createElement('div');

			if (isFav) {
				div.className = 'object favourite';
			} else {
				div.className = 'object';
			}

			div.setAttribute('data-model', pickup);
			div.setAttribute('data-favourite-type', 'pickups');
			div.setAttribute('data-favourite-name', pickup);

			div.innerHTML = pickup;

			div.addEventListener('click', function(event) {
				closePickupMenu(this);
			});

			if (isFav) {
				div.addEventListener('contextmenu', favouriteOnClick);
			} else {
				div.addEventListener('contextmenu', nonFavouriteOnClick);
			}

			pickupList.appendChild(div);
		}
	});
}

function populateBoneNameList(filter) {
	var boneList = document.getElementById('attachment-bone-name');

	boneList.innerHTML = '<option></option>';

	bones.forEach(bone => {
		// Apply filter if provided
		if (!filter || filter === '' || bone.toLowerCase().includes(filter.toLowerCase())) {
			var option = document.createElement('option');
			option.value = bone;
			option.innerHTML = bone;
			boneList.appendChild(option);
		}
	});
}

function populateWalkStyleList(filter) {
	var walkStyleList = document.getElementById('walk-style-list');
	var favsOnly = document.getElementById('favourite-walk-styles').hasAttribute('data-active');

	walkStyleList.innerHTML = '';

	walkStyleBases.forEach(base => {
		walkStyles.forEach(style => {
			var name = base + ': ' + style;
			var isFav = favourites.walkStyles[name];

			if (favsOnly && !isFav) {
				return;
			}

			if (!filter || filter == '' || name.toLowerCase().includes(filter.toLowerCase())) {
				var div = document.createElement('div');

				if (isFav) {
					div.className = 'object favourite';
				} else {
					div.className = 'object';
				}

				div.setAttribute('data-base', base);
				div.setAttribute('data-style', style);
				div.setAttribute('data-favourite-type', 'walkStyles');
				div.setAttribute('data-favourite-name', name);

				div.innerHTML = name;
				div.title = name;

				div.addEventListener('click', function(event) {
					setWalkStyle(this);
				});

				if (isFav) {
					div.addEventListener('contextmenu', favouriteOnClick);
				} else {
					div.addEventListener('contextmenu', nonFavouriteOnClick);
				}

				walkStyleList.appendChild(div);
			}
		});
	});
}

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
	{ menu: 'player-model-menu', back: 'player-model-menu-close-btn' },
	{ menu: 'animation-menu', back: 'animation-menu-close' },
	{ menu: 'lights-options-menu', back: 'lights-options-menu-close' },
	{ menu: 'attachment-options-menu', back: 'attachment-options-menu-close' },
	{ menu: 'ped-options-menu', back: 'ped-options-menu-close' },
	{ menu: 'vehicle-options-menu', back: 'vehicle-options-menu-close' },
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
	document.getElementById('properties-add-to-group').disabled = !permissions.properties.ped.group;
	document.getElementById('properties-remove-from-group').disabled = !permissions.properties.ped.group;
	document.getElementById('properties-scenario').disabled = !permissions.properties.ped.scenario;
	document.getElementById('properties-animation').disabled = !permissions.properties.ped.animation;
	document.getElementById('properties-clear-ped-tasks').disabled = !permissions.properties.ped.clearTasks;
	document.getElementById('properties-clear-ped-tasks-immediately').disabled = !permissions.properties.ped.clearTasks;
	document.getElementById('properties-give-weapon').disabled = !permissions.properties.ped.weapon;
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
		populateSpawnMenu('ped', '', true);
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
					playbackRate: resp.playbackRate
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