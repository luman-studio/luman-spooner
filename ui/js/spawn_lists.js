// ============================================================================
// spooner :: ui/js/spawn_lists.js
// close*Menu handlers, scenario/weapon/animation/walkstyle helpers, and all populate*List functions
//
// Split from ui/script.js. Loaded as a classic <script> in ui/index.html in the
// original source order, so all files share one global scope (behaviour preserved).
// ============================================================================

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

	// RDR3's real eScriptedAnimFlags bits (TASK_PLAY_ANIM, hash 0xEA47FE3719165B94)
	// are NOT the same as the commonly-quoted GTA-style values (16/32 etc.) that
	// were used here originally — that mismatch (in particular accidentally including
	// AF_ABORT_ON_PED_MOVEMENT instead of AF_UPPERBODY/AF_SECONDARY) is why the ped
	// froze and couldn't move. Confirmed bit positions (Halen84/RDR3-Native-Flags-And-Enums):
	//   AF_LOOPING = 1, AF_UPPERBODY = 8, AF_SECONDARY = 16,
	//   AF_DONT_SUPPRESS_LOCO = 65536, AF_UPPERBODY_TAGS = 67108864 (1<<26) — tag-based
	//   sync for the upper-body portion, added alongside AF_UPPERBODY in case the engine
	//   needs it to treat the clip as a true partial overlay instead of a full takeover.
	var AF_UPPERBODY = 8;
	var AF_SECONDARY = 16;
	var AF_DONT_SUPPRESS_LOCO = 65536;
	var AF_UPPERBODY_TAGS = 67108864;

	var flag = parseInt(document.querySelector('#animation-flag').value);
	var filter;

	if (document.querySelector('#animation-allow-running').checked) {
		flag = flag | AF_UPPERBODY | AF_SECONDARY | AF_DONT_SUPPRESS_LOCO | AF_UPPERBODY_TAGS;
		filter = 'BONEMASK_UPPERONLY';
	}

	sendMessage('playAnimation', {
		handle: currentEntity(),
		dict: animation.getAttribute('data-dict'),
		name: animation.getAttribute('data-name'),
		blendInSpeed: parseFloat(document.querySelector('#animation-blend-in-speed').value),
		blendOutSpeed: parseFloat(document.querySelector('#animation-blend-out-speed').value),
		duration: parseInt(document.querySelector('#animation-duration').value),
		flag: flag,
		filter: filter,
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

var pedMoods = [];

function populateEmotionList() {
	var list = document.getElementById('emotion-list');

	list.innerHTML = '';

	pedMoods.forEach(function(mood) {
		var div = document.createElement('div');
		div.className = 'object';
		div.innerHTML = mood;
		div.addEventListener('click', function(event) {
			sendMessage('setPedMood', {
				handle: currentEntity(),
				mood: mood
			});
		});
		list.appendChild(div);
	});
}

// ===================== Emotes (categorized KIT_EMOTE clips) =====================
var emotesData = [];
var currentEmoteCategory = null;

function getEmoteCategory(key) {
	for (var i = 0; i < emotesData.length; i++) {
		if (emotesData[i].category === key) {
			return emotesData[i];
		}
	}
	return null;
}

// The category screen (Reactions, Actions, Taunts, Greetings, Gun Twirls, Dances).
function populateEmotesCategories() {
	var list = document.getElementById('emotes-category-list');
	list.innerHTML = '';

	emotesData.forEach(function(cat) {
		var div = document.createElement('div');
		div.className = 'object';
		div.innerHTML = cat.label + ' <span class="emote-count">' + cat.items.length + '</span>';
		div.addEventListener('click', function(event) {
			openEmoteCategory(cat.category);
		});
		list.appendChild(div);
	});
}

function openEmoteCategory(categoryKey) {
	currentEmoteCategory = categoryKey;
	document.getElementById('emotes-menu').style.display = 'none';
	document.getElementById('emotes-list-menu').style.display = 'flex';
	document.getElementById('emotes-search-filter').value = '';
	populateEmotesList('');
}

// The emote list within the currently-open category.
function populateEmotesList(filter) {
	var list = document.getElementById('emotes-list');
	list.innerHTML = '';

	var cat = getEmoteCategory(currentEmoteCategory);
	if (!cat) {
		return;
	}

	var f = filter ? filter.toLowerCase() : '';

	cat.items.forEach(function(item) {
		if (f && item.label.toLowerCase().indexOf(f) < 0 && item.name.toLowerCase().indexOf(f) < 0) {
			return;
		}

		var div = document.createElement('div');
		div.className = 'object';
		div.innerHTML = item.label;
		div.setAttribute('data-emote', item.name);
		div.addEventListener('click', function(event) {
			document.querySelectorAll('#emotes-list .object').forEach(function(e) {
				e.className = 'object';
			});
			this.className = 'object selected';

			sendMessage('performEmote', {
				handle: currentEntity(),
				emote: item.name
			});
		});
		list.appendChild(div);
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

