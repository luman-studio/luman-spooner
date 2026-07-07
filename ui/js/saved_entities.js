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

// ----- Saved Animation + Prop presets (apply to any selected ped) -----

function openAnimPropsMenu() {
	document.querySelector('#animation-menu').style.display = 'none';
	document.querySelector('#animprops-menu').style.display = 'flex';

	sendMessage('getAnimProps', {}).then(resp => resp.json()).then(resp => updateAnimPropsList(resp));
}

function closeAnimPropsMenu() {
	document.querySelector('#animprops-menu').style.display = 'none';
	document.querySelector('#animation-menu').style.display = 'flex';
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

