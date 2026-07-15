// ============================================================================
// spooner :: ui/js/saved_entities.js
// Placed-particle list, Saved Peds, MP Peds and Animation+Prop preset menus
//
// Split from ui/script.js. Loaded as a classic <script> in ui/index.html in the
// original source order, so all files share one global scope (behaviour preserved).
// ============================================================================

// ----- Placed Particles (view/select/delete particles already placed in the world) -----

function openPlacedParticlesMenu() {
	document.querySelector('#particle-menu').style.display = 'none';
	document.querySelector('#placed-particles-menu').style.display = 'flex';

	sendMessage('getPlacedParticles', {}).then(resp => resp.json()).then(resp => updatePlacedParticlesList(resp));
}

function closePlacedParticlesMenu() {
	document.querySelector('#placed-particles-menu').style.display = 'none';
	document.querySelector('#particle-menu').style.display = 'flex';
}

function updatePlacedParticlesList(data) {
	var list = JSON.parse(data);
	var container = document.querySelector('#placed-particles-list');

	container.innerHTML = '';

	if (!list.length) {
		var empty = document.createElement('div');
		empty.className = 'saved-ped-empty';
		empty.innerHTML = 'No particles placed yet';
		container.appendChild(empty);
		return;
	}

	list.forEach(function(entry) {
		var row = document.createElement('div');
		row.className = 'saved-ped';

		var label = document.createElement('span');
		label.className = 'saved-ped-name';
		label.title = 'Select (move/rotate/scale)';
		label.innerHTML = entry.handle + ' - ' + entry.name + (entry.exists ? '' : ' (gone)');
		label.addEventListener('click', function(event) {
			document.querySelector('#placed-particles-menu').style.display = 'none';
			sendMessage('openPropertiesMenuForEntity', {
				entity: entry.handle
			});
		});

		var deleteBtn = document.createElement('button');
		deleteBtn.className = 'saved-ped-action saved-ped-delete';
		deleteBtn.title = 'Delete';
		deleteBtn.innerHTML = '<i class="fas fa-trash"></i>';
		deleteBtn.addEventListener('click', function(event) {
			event.stopPropagation();

			sendMessage('deleteEntity', {
				handle: entry.handle
			});
			row.remove();

			if (!document.querySelector('#placed-particles-list .saved-ped')) {
				updatePlacedParticlesList('[]');
			}
		});

		row.appendChild(label);
		row.appendChild(deleteBtn);
		container.appendChild(row);
	});
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

// ----- MP Peds (session-based clones, optionally with their horse) -----

function openMpPedsMenu() {
	document.querySelector('#spawn-menu').style.display = 'none';
	document.querySelector('#mp-peds-menu').style.display = 'flex';
	lastSpawnMenu = 6;

	sendMessage('getMpPeds', {}).then(resp => resp.json()).then(resp => updateMpPedsList(resp));
}

function closeMpPedsMenu(spawned) {
	document.querySelector('#mp-peds-menu').style.display = 'none';

	if (!spawned) {
		document.querySelector('#spawn-menu').style.display = 'flex';
		lastSpawnMenu = -1;
	}
}

function updateMpPedsList(data) {
	var names = JSON.parse(data);
	var list = document.querySelector('#mp-peds-list');

	list.innerHTML = '';

	if (!names.length) {
		var empty = document.createElement('div');
		empty.className = 'saved-ped-empty';
		empty.innerHTML = 'No MP peds yet';
		list.appendChild(empty);
		return;
	}

	names.forEach(function(name) {
		list.appendChild(createMpPedRow(name));
	});
}

function createMpPedRow(name) {
	var row = document.createElement('div');
	row.className = 'saved-ped';
	row.setAttribute('data-name', name);

	var label = document.createElement('span');
	label.className = 'saved-ped-name';
	label.title = 'Spawn';
	label.innerHTML = name;
	label.addEventListener('click', function(event) {
		sendMessage('spawnMpPed', {
			name: row.getAttribute('data-name')
		});
		closeMpPedsMenu(true);
	});

	var renameBtn = document.createElement('button');
	renameBtn.className = 'saved-ped-action';
	renameBtn.title = 'Rename';
	renameBtn.innerHTML = '<i class="fas fa-pen"></i>';
	renameBtn.addEventListener('click', function(event) {
		event.stopPropagation();
		startRenameMpPed(row);
	});

	var deleteBtn = document.createElement('button');
	deleteBtn.className = 'saved-ped-action saved-ped-delete';
	deleteBtn.title = 'Delete';
	deleteBtn.innerHTML = '<i class="fas fa-trash"></i>';
	deleteBtn.addEventListener('click', function(event) {
		event.stopPropagation();

		sendMessage('deleteMpPed', {
			name: row.getAttribute('data-name')
		});
		row.remove();

		if (!document.querySelector('#mp-peds-list .saved-ped')) {
			updateMpPedsList('[]');
		}
	});

	row.appendChild(label);
	row.appendChild(renameBtn);
	row.appendChild(deleteBtn);

	return row;
}

function startRenameMpPed(row) {
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

		sendMessage('renameMpPed', {
			oldName: oldName,
			newName: newName
		}).then(resp => resp.json()).then(resp => updateMpPedsList(resp));
	}

	function cancel() {
		row.replaceWith(createMpPedRow(oldName));
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

// ----- Create Custom / Customize (manual per-slot ped editor) -----

// Handle of the ped currently open in the editor, so the Save button knows what
// to save regardless of whether it's a fresh temp ped or an existing selected one.
var customPedEditingHandle = null;

function openCustomMpPedMenu(gender) {
	document.querySelector('#mp-peds-menu').style.display = 'none';
	document.querySelector('#mp-custom-menu').style.display = 'flex';

	sendMessage('openCustomMpPed', { gender: gender || 'male' }).then(resp => resp.json()).then(resp => renderCustomMpPed(resp));
}

// Ped Options -> Customize: edit the currently selected ped in place instead of
// spawning a new one.
function openCustomizePedMenu(handle) {
	document.querySelector('#properties-menu').style.display = 'none';
	document.querySelector('#ped-options-menu').style.display = 'none';
	document.querySelector('#mp-custom-menu').style.display = 'flex';

	sendMessage('openCustomizePed', { handle: handle }).then(resp => resp.json()).then(resp => renderCustomMpPed(resp));
}

// The ped is already spawned/selected by the time this menu opens, so closing it
// (like Create Random) exits the whole spawn menu rather than going back a level.
function closeCustomMpPedMenu() {
	document.querySelector('#mp-custom-menu').style.display = 'none';
	customPedEditingHandle = null;
	sendMessage('closeCustomMpPed', {});
}

function formatCustomCategoryLabel(category) {
	return category
		.replace(/_/g, ' ')
		.replace(/([a-z])([A-Z])/g, '$1 $2')
		.replace(/\b\w/g, function(c) { return c.toUpperCase(); });
}

function renderCustomMpPed(data) {
	if (typeof data === 'string') {
		data = JSON.parse(data);
	}

	if (!data || !data.categories) {
		return;
	}

	if (typeof data.handle !== 'undefined') {
		customPedEditingHandle = data.handle;
	}

	// Gender is locked (hidden) when editing an already-existing ped — switching it
	// would mean deleting that ped and spawning a different model in its place.
	document.querySelector('#mp-custom-gender-row').style.display = data.genderLocked ? 'none' : 'flex';
	document.querySelector('#mp-custom-gender-male').classList.toggle('selected', data.gender === 'male');
	document.querySelector('#mp-custom-gender-female').classList.toggle('selected', data.gender === 'female');

	// Horses wear tack, not clothing — "Save as MP ped" makes no sense for them, so
	// hide the save row; live tack edits persist to the horse's Database entry.
	document.querySelector('#mp-custom-save-row').style.display = data.isHorse ? 'none' : 'flex';

	var list = document.querySelector('#mp-custom-list');
	list.innerHTML = '';

	// Rows arrive already grouped (Body, Hair, Clothing) by the Lua side — insert a
	// header whenever the group changes instead of every row carrying its own.
	var lastGroup = null;

	data.categories.forEach(function(entry) {
		if (entry.group && entry.group !== lastGroup) {
			var header = document.createElement('div');
			header.className = 'custom-ped-section-header';
			header.textContent = entry.group;
			list.appendChild(header);
			lastGroup = entry.group;
		}

		list.appendChild(createCustomPedRow(entry));
	});
}

function updateCustomPedRowDisplay(row, index, count) {
	var input = row.querySelector('.custom-ped-row-input');

	input.value = index;
	input.max = count;
	row.classList.toggle('is-none', index === 0);
}

function createCustomPedRow(entry) {
	var row = document.createElement('div');
	row.className = 'custom-ped-row' + (entry.required ? ' required' : '') + (entry.index === 0 ? ' is-none' : '');
	row.setAttribute('data-category', entry.category);

	// Prefer an explicit label from the backend (horse tack rows send nicely
	// formatted names like "Saddle Horn"); otherwise title-case the category key.
	var labelText = entry.label || formatCustomCategoryLabel(entry.category);
	var label = document.createElement('span');
	label.className = 'custom-ped-row-label';
	label.title = labelText;
	label.innerHTML = labelText;

	var prevBtn = document.createElement('button');
	prevBtn.className = 'custom-ped-row-btn';
	prevBtn.innerHTML = '<i class="fas fa-chevron-left"></i>';
	prevBtn.addEventListener('click', function(event) {
		cycleCustomPedCategory(entry.category, -1, row);
	});

	// Just the editable index — no "/ total" (only shown once, in the tooltip),
	// so every row lines up the same regardless of how many options a slot has.
	var input = document.createElement('input');
	input.type = 'number';
	input.className = 'custom-ped-row-input';
	input.title = '1-' + entry.count;
	input.min = entry.required ? 1 : 0;
	input.max = entry.count;
	input.step = 1;
	input.value = entry.index;
	input.addEventListener('keydown', function(event) {
		if (event.key === 'Enter') {
			event.preventDefault();
			input.blur();
		}
		event.stopPropagation();
	});
	input.addEventListener('change', function(event) {
		setCustomPedIndex(entry.category, parseInt(input.value, 10) || 0, row);
	});

	var nextBtn = document.createElement('button');
	nextBtn.className = 'custom-ped-row-btn';
	nextBtn.innerHTML = '<i class="fas fa-chevron-right"></i>';
	nextBtn.addEventListener('click', function(event) {
		cycleCustomPedCategory(entry.category, 1, row);
	});

	// Always add the None button, even on required rows (disabled + hidden there),
	// so every row has the same number of columns and nothing shifts left/right.
	var noneBtn = document.createElement('button');
	noneBtn.className = 'custom-ped-row-btn custom-ped-row-none';
	noneBtn.title = 'Set to None';
	noneBtn.innerHTML = '<i class="fas fa-ban"></i>';

	if (entry.required) {
		noneBtn.disabled = true;
		noneBtn.classList.add('hidden-btn');
	} else {
		noneBtn.addEventListener('click', function(event) {
			setCustomPedIndex(entry.category, 0, row);
		});
	}

	row.appendChild(label);
	row.appendChild(prevBtn);
	row.appendChild(input);
	row.appendChild(nextBtn);
	row.appendChild(noneBtn);

	// Some items (bandanas, hats...) have more than one worn position (down vs
	// pulled up over the face, etc) — this toggles between them without changing
	// which item is equipped.
	if (entry.hasState) {
		var stateBtn = document.createElement('button');
		stateBtn.className = 'custom-ped-row-btn custom-ped-row-state';
		stateBtn.title = 'Toggle worn position (e.g. bandana up/down)';
		stateBtn.innerHTML = '<i class="fas fa-sync-alt"></i>';
		stateBtn.addEventListener('click', function(event) {
			sendMessage('customPedToggleWearableState', { category: entry.category });
		});
		row.appendChild(stateBtn);
	}

	return row;
}

// If the backend hands back a full `categories` list (horse mane/tail Style changes
// add or remove the paired Color row), re-render the whole list; otherwise just
// patch the single row that changed.
function applyCustomPedCycleResult(raw, row) {
	var entry = typeof raw === 'string' ? JSON.parse(raw) : raw;

	if (!entry || typeof entry.index === 'undefined') {
		return;
	}

	if (entry.categories) {
		renderCustomMpPed({ categories: entry.categories, genderLocked: true, isHorse: true, gender: 'male' });
	} else {
		updateCustomPedRowDisplay(row, entry.index, entry.count);
	}
}

function cycleCustomPedCategory(category, direction, row) {
	sendMessage('customPedCycle', { category: category, direction: direction }).then(resp => resp.json()).then(function(raw) {
		applyCustomPedCycleResult(raw, row);
	});
}

function setCustomPedIndex(category, index, row) {
	sendMessage('customPedSetIndex', { category: category, index: index }).then(resp => resp.json()).then(function(raw) {
		applyCustomPedCycleResult(raw, row);
	});
}

// ----- Saved Animation + Prop presets (apply to any selected ped) -----

function openAnimPropsMenu() {
	document.querySelector('#animation-anims-menu').style.display = 'none';
	document.querySelector('#animprops-menu').style.display = 'flex';

	sendMessage('getAnimProps', {}).then(resp => resp.json()).then(resp => updateAnimPropsList(resp));
}

function closeAnimPropsMenu() {
	document.querySelector('#animprops-menu').style.display = 'none';
	document.querySelector('#animation-anims-menu').style.display = 'flex';
}

function updateAnimPropsList(data) {
	var names = JSON.parse(data);
	var list = document.querySelector('#animprops-list');

	list.innerHTML = '';

	if (!names.length) {
		var empty = document.createElement('div');
		empty.className = 'saved-ped-empty';
		empty.innerHTML = 'No saved animations+props yet';
		list.appendChild(empty);
		return;
	}

	names.forEach(function(name) {
		list.appendChild(createAnimPropRow(name));
	});
}

function createAnimPropRow(name) {
	var row = document.createElement('div');
	row.className = 'saved-ped';
	row.setAttribute('data-name', name);

	var label = document.createElement('span');
	label.className = 'saved-ped-name';
	label.title = 'Apply to selected ped';
	label.innerHTML = name;
	label.addEventListener('click', function(event) {
		sendMessage('applyAnimProp', {
			handle: currentEntity(),
			name: row.getAttribute('data-name')
		});
		closeAnimPropsMenu();
	});

	var renameBtn = document.createElement('button');
	renameBtn.className = 'saved-ped-action';
	renameBtn.title = 'Rename';
	renameBtn.innerHTML = '<i class="fas fa-pen"></i>';
	renameBtn.addEventListener('click', function(event) {
		event.stopPropagation();
		startRenameAnimProp(row);
	});

	var deleteBtn = document.createElement('button');
	deleteBtn.className = 'saved-ped-action saved-ped-delete';
	deleteBtn.title = 'Delete';
	deleteBtn.innerHTML = '<i class="fas fa-trash"></i>';
	deleteBtn.addEventListener('click', function(event) {
		event.stopPropagation();

		sendMessage('deleteAnimProp', {
			name: row.getAttribute('data-name')
		});
		row.remove();

		if (!document.querySelector('#animprops-list .saved-ped')) {
			updateAnimPropsList('[]');
		}
	});

	row.appendChild(label);
	row.appendChild(renameBtn);
	row.appendChild(deleteBtn);

	return row;
}

function startRenameAnimProp(row) {
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

		sendMessage('renameAnimProp', {
			oldName: oldName,
			newName: newName
		}).then(resp => resp.json()).then(resp => updateAnimPropsList(resp));
	}

	function cancel() {
		row.replaceWith(createAnimPropRow(oldName));
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

