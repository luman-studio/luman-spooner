Config = {}

Config.isRDR = not TerraingridActivate

-- Configurable controls
if Config.isRDR then
	-- RDR2 Controls. Mouse Buttons not detectable as Raw Keys.
	Config.SelectControl          = `INPUT_CURSOR_ACCEPT` -- Left mouse button
	Config.DeleteControl          = `INPUT_CONTEXT_LT` -- Right mouse button
	Config.LookLrControl          = `INPUT_LOOK_LR`
	Config.LookUdControl          = `INPUT_LOOK_UD`
else
	-- GTA V Controls. Mouse Buttons not detectable as Raw Keys.
	Config.SelectControl          = 176   -- Left mouse button
	Config.DeleteControl          = 177   -- Right mouse button
	Config.LookLrControl          = 176   -- Left mouse button
	Config.LookUdControl          = 177   -- Right mouse button
end
-- Raw keys:
Config.IncreaseSpeedControl   = 33  -- Page Up
Config.DecreaseSpeedControl   = 34  -- Page Down
Config.UpControl              = 32  -- Spacebar
Config.DownControl            = 160  -- Left Shift
Config.ForwardControl         = 87  -- W
Config.BackwardControl        = 83  -- S
Config.LeftControl            = 65  -- A
Config.RightControl           = 68  -- D
Config.ToggleControl          = 46  -- Del
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
