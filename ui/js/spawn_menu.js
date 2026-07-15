// ============================================================================
// spooner :: ui/js/spawn_menu.js
// Global UI state vars and the unified spawn-menu system (config, paging, filtering, keyboard nav)
//
// Split from ui/script.js. Loaded as a classic <script> in ui/index.html in the
// original source order, so all files share one global scope (behaviour preserved).
// ============================================================================

var isSpoonerHudOpened = false;
var peds = [];
var horses = [];
var vehicles = [];
var objects = [];
var scenarios = [];
var weapons = [];
var animations = {};
var propsets = [];
var pickups = [];
var particles = [];
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
	// Horses are ped models (a_c_horse_*) — same spawn/preview Lua callbacks as peds,
	// just a horse-only data source. Tack customization happens afterwards via
	// Ped Options -> Customize (which auto-detects horses).
	horse: {
		id: 'horse',
		dataSource: function() { return horses; },
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
	},
	particle: {
		id: 'particle',
		dataSource: function() { return particles; },
		favouriteType: 'particles',
		closeMessage: 'closeParticleMenu',
		previewMessage: 'previewParticle',
		spawnAttachMessage: 'spawnAndAttachParticle',
		clearPreviewMessage: 'clearParticlePreview',
		supportsPreview: true,
		supportsAttach: true
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
