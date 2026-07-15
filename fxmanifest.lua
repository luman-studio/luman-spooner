fx_version "cerulean"
game "common"
rdr3_warning "I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships."

name "spooner"
author "kibukj"
description "Entity spawner for FiveM and RedM"
repository "https://github.com/kibook/spooner"

files {
	"ui/index.html",
	"ui/font-awesome.min.css",
	"ui/style.css",
	"ui/keyboard.ttf",
	"ui/style_extended.css",
	"ui/js/extended.js",
	"ui/js/spawn_menu.js",
	"ui/js/hud.js",
	"ui/js/saved_entities.js",
	"ui/js/spawn_lists.js",
	"ui/js/properties.js",
	"ui/js/database_ui.js",
	"ui/js/main.js",

	"ui/gta5.css",
	"ui/pricedown.otf",
	"ui/rdr3.css",
	"ui/chineserocks.ttf",

	-- Both games' data files are shipped to the client with a glob; the explicit
	-- load list lives in the `spooner_data` metadata below.
	"data/gta5/*.lua",
	"data/rdr3/*.lua",
}

-- Which data files client/data_loader.lua actually executes, enumerated at
-- runtime via GetResourceMetadata. This is a custom metadata key (like ox_lib's
-- own `ox_lib` key) — NOT the built-in `files`/`data_file` directives, which are
-- handled specially and don't enumerate back as a plain list. The loader loads
-- only the entries whose path matches the running game (data/<game>/...).
spooner_data "data/gta5/animations.lua"
spooner_data "data/gta5/bones.lua"
spooner_data "data/gta5/interiors.lua"
spooner_data "data/gta5/objects.lua"
spooner_data "data/gta5/pedConfigFlags.lua"
spooner_data "data/gta5/peds.lua"
spooner_data "data/gta5/pickups.lua"
spooner_data "data/gta5/propsets.lua"
spooner_data "data/gta5/scenarios.lua"
spooner_data "data/gta5/vehicles.lua"
spooner_data "data/gta5/walkstyles.lua"
spooner_data "data/gta5/weapons.lua"

spooner_data "data/rdr3/animations.lua"
spooner_data "data/rdr3/bodies.lua"
spooner_data "data/rdr3/bones.lua"
spooner_data "data/rdr3/objects.lua"
spooner_data "data/rdr3/outfits.lua"
spooner_data "data/rdr3/particles.lua"
spooner_data "data/rdr3/pedConfigFlags.lua"
spooner_data "data/rdr3/peds.lua"
spooner_data "data/rdr3/pickups.lua"
spooner_data "data/rdr3/propsets.lua"
spooner_data "data/rdr3/scenarios.lua"
spooner_data "data/rdr3/tack.lua"
spooner_data "data/rdr3/vehicles.lua"
spooner_data "data/rdr3/walkstyles.lua"
spooner_data "data/rdr3/weapons.lua"

ui_page "ui/index.html"

shared_scripts {
	"config.lua"
}

server_scripts {
	"server/permissions.lua",
	"server/events.lua",
	"server/extended.lua",
}

client_script "slaxml.lua"

client_script "client/data_loader.lua"
client_script "client/uiprompt.lua"
client_scripts {
	"client/core.lua",
	"client/entities.lua",
	"client/spawn.lua",
	"client/nui_preview.lua",
	"client/nui_spawn.lua",
	"client/database.lua",
	"client/peds.lua",
	"client/behavior.lua",
	"client/export.lua",
	"client/nui_entity.lua",
	"client/main.lua",
}
