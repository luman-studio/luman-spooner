Config = {}

Config.isRDR = not TerraingridActivate

-- Configurable controls
if Config.isRDR then
	-- RDR2 Controls. Mouse Buttons not detectable as Raw Keys.
	Config.SelectControl          = `INPUT_CURSOR_ACCEPT` -- Left mouse button
	Config.DeleteControl          = `INPUT_CONTEXT_LT` -- Right mouse button
	Config.LookLrControl          = `INPUT_LOOK_LR`
	Config.LookUdControl          = `INPUT_LOOK_UD`
	Config.IncreaseSpeedControl   = `INPUT_CURSOR_SCROLL_UP`   -- Mouse wheel up
	Config.DecreaseSpeedControl   = `INPUT_CURSOR_SCROLL_DOWN` -- Mouse wheel down
	-- RDR3 references controls by joaat hash.
	Config.TextChatControl        = `INPUT_MP_TEXT_CHAT_ALL`
	Config.PauseControl           = `INPUT_FRONTEND_PAUSE`
	Config.PauseAlternateControl  = `INPUT_FRONTEND_PAUSE_ALTERNATE`
else
	-- GTA V Controls. Mouse Buttons not detectable as Raw Keys.
	Config.SelectControl          = 176   -- Left mouse button
	Config.DeleteControl          = 177   -- Right mouse button
	Config.LookLrControl          = 1
	Config.LookUdControl          = 2
	Config.IncreaseSpeedControl   = 241   -- Mouse wheel up (INPUT_CURSOR_SCROLL_UP)
	Config.DecreaseSpeedControl   = 242   -- Mouse wheel down (INPUT_CURSOR_SCROLL_DOWN)
	-- GTA V references controls by integer index. Passing a joaat hash here indexes
	-- the control array out of bounds and crashes the game (native 0x91AEF906BCA88877).
	Config.TextChatControl        = 245   -- INPUT_MP_TEXT_CHAT_ALL
	Config.PauseControl           = 199   -- INPUT_FRONTEND_PAUSE
	Config.PauseAlternateControl  = 200   -- INPUT_FRONTEND_PAUSE_ALTERNATE
end
-- Raw keys:
Config.UpControl              = 32  -- Spacebar
Config.DownControl            = 160  -- Left Shift
Config.ForwardControl         = 87  -- W
Config.BackwardControl        = 83  -- S
Config.LeftControl            = 65  -- A
Config.RightControl           = 68  -- D
Config.ToggleControl          = 116  -- F5 (Open Spooner)
Config.SpawnControl           = 69  -- E
Config.AdjustUpControl        = 81  -- Q
Config.AdjustDownControl      = 90  -- Z
Config.AdjustForwardControl   = 38  -- Up arrow key
Config.AdjustBackwardControl  = 40  -- Down arrow key
Config.AdjustLeftControl      = 37  -- Left arrow key
Config.AdjustRightControl     = 39  -- Right arrow key
Config.RotateRightControl     = 67  -- C
Config.RotateLeftControl      = 86  -- V
Config.RotateModeControl      = 66  -- B
Config.SpawnMenuControl       = 70  -- F
Config.DbMenuControl          = 88  -- X
Config.PropMenuControl        = 9   -- Tab
Config.SaveLoadDbMenuControl  = 74  -- J
Config.AdjustModeControl      = 73  -- I
Config.PlaceOnGroundControl   = 85  -- U
Config.FreeAdjustModeControl  = 56  -- 8
Config.AdjustOffControl       = 55  -- 7
Config.HelpMenuControl        = 72  -- H
Config.CloneControl           = 71  -- G
Config.SpeedModeControl       = 82  -- R
Config.ToggleControlsControl  = 49  -- 1
Config.FocusControl           = 164  -- Left Alt
Config.ToggleFocusModeControl = 162  -- Left Ctrl
Config.EntityHandlesControl   = 77  -- M
Config.CopyCameraToClipboard  = 50 -- 2

-- Maximum movement speed
Config.MaxSpeed = 1.00

-- Minimum movement speed
Config.MinSpeed = 0.01

-- How much the speed increases/decreases by when the speed up/down controls are pressed
Config.SpeedIncrement = 0.01

-- Default movement speed
Config.Speed = 0.10

-- Camera rotation X-axis speed
Config.SpeedLr = 8.0

-- Camera rotation Y-axis speed
Config.SpeedUd = 8.0

-- Minimum X, Y, Z adjustment speed
Config.MinAdjustSpeed = 0.001

-- Maximum X, Y, Z adjustment speed
Config.MaxAdjustSpeed = 100.0

-- How much the X, Y, Z adjust speed increases/decreases by when the speed up/down controls are pressed
Config.AdjustSpeedIncrement = 0.001

-- Speed of X, Y, Z adjustments
Config.AdjustSpeed = 0.01

-- Minimum speed of pitch, roll, yaw adjustments
Config.MinRotateSpeed = 0.1

-- Maximum speed of pitch, roll, yaw adjustments
Config.MaxRotateSpeed = 360.0

-- How much the pitch, roll, yaw adjust speed increases/decreased by when the speed up/down controls are pressed
Config.RotateSpeedIncrement = 0.1

-- Speed of pitch, roll, yaw adjustments
Config.RotateSpeed = 1.0

-- Radar blip sprite for group members
Config.GroupMemberBlipSprite = -214162151

-- Max entities that can be spawned at a time by players without spooner.noEntityLimit
Config.MaxEntities = 10

-- Whether to automatically remove all entities from players' databases when the resource is stopped
Config.CleanUpOnStop = true

-- Draw distance for entity handles
Config.EntityHandleDrawDistance = 20.0

-- Highest ped component slot index captured/restored when persisting an MP ped's
-- look to disk (0..N inclusive). RDR3 has no GTA-style integer component/drawable/
-- texture variation natives, so this only matters as a best-effort fallback for a
-- captured *live* MP ped (see CaptureComponents in client/peds.lua) — it is not
-- used by "Randomize All", which builds an explicit per-slot config instead (see
-- Config.RandomOutfitChance below).
Config.MpPedComponentSlots = 20

-- "Randomize All" (MP Peds -> Create Custom) builds its outfit from data/rdr3/
-- outfits.lua (real RDR3 clothing shop-item hashes, one entry per category/slot).
-- Deliberately narrow by design — only Pant/Skirt (or Dress), Shirt and Boots are
-- always applied (plus body/head/hair/beard — see RandomizeCustomBodyAppearance in
-- client/peds.lua), and ONLY the categories listed below are ever added on top,
-- each independently at this chance (0..1). Everything else (belts, gunbelts,
-- rings, masks, satchels, holsters, badges, armor...) is left for the player to add
-- by hand — a random ped shouldn't come pre-loaded with accessories nobody asked
-- for. Coat/CoatClosed/Vest are mutually exclusive layers on top of Shirt — only
-- one survives regardless of how many happened to roll true (see RandomizeCustomList).
Config.RandomOutfitChance = {
	Hat = 0.5,
	Coat = 0.2,
	CoatClosed = 0.15,
	Vest = 0.2,
	Glove = 0.3
}

-- Facial hair (male only — see PedBeardData in data/rdr3/bodies.lua) chance for
-- "Randomize All".
Config.RandomBeardChance = 0.35

-- Placed particle effects are attached to a small, forced-invisible "anchor"
-- object (the particle itself is the only visible thing), so this model choice
-- doesn't matter beyond needing to exist and stream reliably.
Config.ParticleAnchorModel = 'dummy_gfx_test'

-- Patrol + Lasso behavior
Config.PatrolLassoWeapon = 'WEAPON_LASSO'     -- weapon equipped for the twirl
Config.PatrolMoveSpeed   = 2.0                -- 1.0 walk, 2.0 run, 3.0 sprint
Config.PatrolReachDist   = 1.5                -- how close to B counts as "arrived"
Config.PatrolTimeout     = 20000             -- safety timeout per A->B leg (ms)

-- Optional over-head lasso twirl animation. RDR2's own "aim lasso" twirl is a
-- player mechanic that AI peds don't perform, so aiming alone won't spin the lasso.
-- When dict/name are set, the behavior switches to "run + twirl animation" mode:
-- the ped runs (lower body via the go-to task) and this clip plays only on the
-- upper body via the bone-mask filter. Leave dict empty to fall back to aim mode.
--   blendIn/blendOut = plain blend speeds (positive), same as a normal TaskPlayAnim call.
--   flag   = anim flag, using RDR3's real eScriptedAnimFlags bit positions (these are
--            NOT the commonly-quoted GTA-style values): AF_LOOPING=1, AF_UPPERBODY=8,
--            AF_SECONDARY=16. 25 = loop + upperbody + secondary, so it layers over the
--            running task and repeats (a hard loop — may show a small seam).
--   filter = bone-mask so only the upper body is animated and the legs keep running.
--            Try 'BONEMASK_UPPERONLY'; if the legs still move, try 'BONEMASK_HEADNECKANDARMS'
--            or leave '' to animate the whole body.
Config.LassoTwirlAnim = {
	dict = 'mech_weapons_special@lasso@base@swing@sweep',
	name = 'aim_med_0',
	blendIn = 1.0,
	blendOut = 1.0,
	flag = 25,
	filter = 'BONEMASK_UPPERONLY'
}
